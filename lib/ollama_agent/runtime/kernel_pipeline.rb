# frozen_string_literal: true

require "digest"
require "json"

require_relative "logical_clock"

module OllamaAgent
  module Runtime
    # End-to-end kernel route: saga, locks, atomic write, verify, integration queue, commit/compensate.
    # rubocop:disable Metrics/ClassLength -- FSM orchestration; assembly holds wiring
    class KernelPipeline
      def self.build_for_workspace(...)
        KernelPipelineAssembly.build_for_workspace(...)
      end

      # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength -- explicit runtime wiring per E13
      def initialize(workspace_root:, database_registry:, ownership_index:, fencing_allocator:, lock_manager:,
                     intent_reservation:, atomic_mutator:, saga_coordinator:, isolated_validator:,
                     post_condition_verifier:, blob_store:, compensation_manifest:, compensation_engine:,
                     saga_recovery_daemon:, integration_queue:, wal:, clock_epoch_provider:)
        @workspace_root = workspace_root
        @database_registry = database_registry
        @ownership_index = ownership_index
        @fencing_allocator = fencing_allocator
        @lock_manager = lock_manager
        @intent_reservation = intent_reservation
        @atomic_mutator = atomic_mutator
        @saga_coordinator = saga_coordinator
        @isolated_validator = isolated_validator
        @post_condition_verifier = post_condition_verifier
        @blob_store = blob_store
        @compensation_manifest = compensation_manifest
        @compensation_engine = compensation_engine
        @saga_recovery_daemon = saga_recovery_daemon
        @integration_queue = integration_queue
        @wal = wal
        @clock_epoch_provider = clock_epoch_provider
      end
      # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength

      # @return [Hash] +:result+ (:ok / :error), +:state+ (terminal saga state), +:manifest_id+
      # rubocop:disable Metrics/MethodLength -- linear orchestration entry
      def execute(intent:, manifest_id:, mode: "normal")
        intent = normalize_intent(intent)
        return terminal_payload(manifest_id, :error, "intent kind must be atomic_write") unless atomic_write?(intent)

        stamp = LogicalClock.new(epoch: @clock_epoch_provider.call.to_i)
        scopes = normalize_scopes(intent)
        intent_hash = compute_intent_hash(intent, scopes)
        started = @saga_coordinator.start(manifest_id: manifest_id, intent_hash: intent_hash,
                                          planned_scopes: scopes, metadata: {})
        return terminal_payload(manifest_id, :error, "saga start #{started}") unless started == :reserved

        lock_outcome = acquire_locks!(manifest_id, scopes)
        return lock_outcome if lock_outcome[:result] == :error

        advance_or_fail(:locked, "locked", manifest_id, lock_outcome[:leases], intent, intent_hash, stamp, mode)
      end
      # rubocop:enable Metrics/MethodLength

      private

      # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength, Metrics/AbcSize -- private saga steps
      attr_reader :saga_coordinator, :lock_manager, :atomic_mutator, :post_condition_verifier,
                  :compensation_engine, :integration_queue, :blob_store, :compensation_manifest,
                  :clock_epoch_provider, :workspace_root

      def atomic_write?(intent)
        intent[:kind].to_s == "atomic_write"
      end

      def normalize_intent(intent)
        h = intent.transform_keys(&:to_sym)
        h[:post_conditions] = Array(h[:post_conditions])
        h[:scopes] = Array(h[:scopes]) if h[:scopes]
        h
      end

      def compute_intent_hash(intent, scopes_for_saga)
        body = {
          "kind" => intent[:kind].to_s,
          "path" => intent[:path].to_s,
          "scopes" => scopes_for_saga.map(&:to_s)
        }
        Digest::SHA256.hexdigest(JSON.generate(body))
      end

      def normalize_scopes(intent)
        abs_target = File.expand_path(intent[:path].to_s, @workspace_root)
        list = intent[:scopes]
        scopes = list.nil? || list.empty? ? [abs_target] : list.map { |s| File.expand_path(s.to_s, @workspace_root) }
        scopes.uniq.sort
      end

      def acquire_locks!(manifest_id, scopes)
        leases = []
        scopes.each do |scope|
          epoch = clock_epoch_provider.call.to_i
          acq = lock_manager.acquire(scope: scope, holder: manifest_id, ttl_epochs: 120, current_epoch: epoch)
          return abort_compensated(manifest_id, leases, "lock failed for #{scope}") unless acq.is_a?(Hash)

          leases << {
            scope: scope,
            holder: manifest_id,
            lease_token: acq[:lease_token],
            fencing_token: acq[:fencing_token]
          }
        end
        { leases: leases, result: :ok }
      end

      def advance_or_fail(state, reason, manifest_id, lease_handles, intent, intent_hash, stamp, mode)
        ok = saga_coordinator.advance(manifest_id: manifest_id, to_state: state, reason: reason)
        return abort_compensated(manifest_id, lease_handles, "advance #{state} #{ok}") unless ok == :ok

        mutate_verify_and_commit(manifest_id, lease_handles, intent, intent_hash, stamp, mode)
      end

      def mutate_verify_and_commit(manifest_id, lease_handles, intent, intent_hash, stamp, mode)
        absolute = File.expand_path(intent[:path].to_s, @workspace_root)
        lease = lease_handles.find { |h| h[:scope] == absolute } || lease_handles.last
        record_pre_state!(manifest_id, absolute, lease[:fencing_token], stamp)

        write_outcome = apply_atomic_write(intent, intent_hash, manifest_id, stamp, mode, lease[:fencing_token])
        unless write_outcome == :written
          return abort_compensated(manifest_id, lease_handles, "mutator #{write_outcome}")
        end

        ok = saga_coordinator.advance(manifest_id: manifest_id, to_state: :mutations_applied,
                                      reason: "mutations_applied")
        return abort_compensated(manifest_id, lease_handles, "advance mutations_applied #{ok}") unless ok == :ok

        verify_outcome = post_condition_verifier.verify(
          manifest_id: manifest_id,
          checks: intent[:post_conditions],
          logical_stamp: stamp.next_stamp
        )
        return abort_compensated(manifest_id, lease_handles, "post_condition failed") unless verify_outcome[:passed]

        commit_success_path(manifest_id, lease_handles, stamp)
      end

      def record_pre_state!(manifest_id, absolute, fencing_token, stamp)
        logical_stamp = stamp.next_stamp
        if File.file?(absolute)
          sha = blob_store.put(File.binread(absolute))
          record_compensation(manifest_id, absolute, sha, 1, fencing_token, logical_stamp)
        else
          record_compensation(manifest_id, absolute, "", 0, fencing_token, logical_stamp)
        end
      end

      def record_compensation(manifest_id, path, sha, pre_existed, fencing_token, logical_stamp)
        compensation_manifest.record(
          manifest_id: manifest_id,
          path: path,
          op: "atomic_write",
          pre_blob_sha: sha,
          pre_existed: pre_existed,
          fencing_token: fencing_token,
          logical_stamp: logical_stamp
        )
      end

      def apply_atomic_write(intent, intent_hash, manifest_id, stamp, mode, fencing_token)
        atomic_mutator.write(
          path: intent[:path].to_s,
          content: intent[:content].to_s,
          mode: mode.to_s,
          fencing_token: fencing_token,
          expected_pre_hash: intent[:expected_pre_hash],
          intent_hash: intent_hash,
          manifest_id: manifest_id,
          logical_stamp: stamp.next_stamp,
          owner_required: intent[:owner_required],
          supervisor_lease: intent[:supervisor_lease] || false
        )
      end

      def commit_success_path(manifest_id, leases, stamp)
        v = saga_coordinator.advance(manifest_id: manifest_id, to_state: :verified, reason: "verified")
        return abort_compensated(manifest_id, leases, "advance verified #{v}") unless v == :ok

        q = saga_coordinator.advance(manifest_id: manifest_id, to_state: :integration_queued,
                                     reason: "integration_queued")
        return abort_compensated(manifest_id, leases, "advance integration_queued #{q}") unless q == :ok

        integration_queue.enqueue(
          manifest_id: manifest_id,
          payload: JSON.generate("kind" => "atomic_write"),
          created_at: stamp.next_stamp
        )

        c = saga_coordinator.advance(manifest_id: manifest_id, to_state: :committed, reason: "committed")
        return abort_compensated(manifest_id, leases, "advance committed #{c}") unless c == :ok

        release_locks(leases)
        snap = saga_coordinator.state_of(manifest_id: manifest_id)
        { result: :ok, state: snap[:state], manifest_id: manifest_id }
      end
      # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength, Metrics/AbcSize

      def abort_compensated(manifest_id, leases, reason)
        release_locks(leases)
        epoch = clock_epoch_provider.call.to_s
        compensation_engine.compensate(manifest_id: manifest_id, logical_stamp: epoch)
        saga_coordinator.compensate(manifest_id: manifest_id, reason: reason)
        snapshot_after_abort(manifest_id)
      end

      def snapshot_after_abort(manifest_id)
        snap = saga_coordinator.state_of(manifest_id: manifest_id)
        { result: :error, state: snap[:state], manifest_id: manifest_id }
      end

      def terminal_payload(manifest_id, result, error)
        snap = saga_coordinator.state_of(manifest_id: manifest_id)
        { result: result, state: snap&.fetch(:state, nil), manifest_id: manifest_id, error: error }
      end

      def release_locks(leases)
        leases.reverse_each do |h|
          lock_manager.release(scope: h[:scope], holder: h[:holder], lease_token: h[:lease_token])
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

require_relative "kernel_pipeline_assembly"

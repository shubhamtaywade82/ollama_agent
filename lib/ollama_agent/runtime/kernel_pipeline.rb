# frozen_string_literal: true

require "digest"
require "json"
require "pathname"

require_relative "../security/resource_guard"
require_relative "criticality_policy"
require_relative "execution_mode"
require_relative "cas_guard"
require_relative "logical_clock"
require_relative "unified_diff_apply"

module OllamaAgent
  module Runtime
    # End-to-end kernel route: saga, locks, atomic write, verify, integration queue, commit/compensate.
    # rubocop:disable Metrics/ClassLength -- FSM orchestration; assembly holds wiring
    class KernelPipeline
      SUPPORTED_KINDS = %w[atomic_write edit_file apply_patch delete_file rename_file].freeze

      def self.build_for_workspace(...)
        KernelPipelineAssembly.build_for_workspace(...)
      end

      # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength, Metrics/AbcSize -- explicit runtime wiring per E13
      def initialize(workspace_root:, database_registry:, ownership_index:, fencing_allocator:, lock_manager:,
                     intent_reservation:, atomic_mutator:, saga_coordinator:, isolated_validator:,
                     post_condition_verifier:, blob_store:, compensation_manifest:, compensation_engine:,
                     saga_recovery_daemon:, integration_queue:, wal:, clock_epoch_provider:, hooks: nil)
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
        @hooks = hooks
      end
      # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength, Metrics/AbcSize

      # @return [Hash] +:result+, +:state+, +:manifest_id+, optional +:error+
      # rubocop:disable Metrics/MethodLength -- guard + single orchestration entry
      def execute(intent:, manifest_id:, mode: "normal")
        intent = normalize_intent(intent)
        kind = intent[:kind].to_s
        unless SUPPORTED_KINDS.include?(kind)
          return emit_pipeline_complete(manifest_id, unknown_kind_reply(manifest_id, kind))
        end

        ge = guard_delete_rename_paths_if_applicable(intent, kind)
        if ge
          payload = { result: :precondition_failed, state: nil, manifest_id: manifest_id, error: ge }
          return emit_pipeline_complete(manifest_id, payload)
        end

        emit_pipeline_complete(manifest_id, run_after_path_guard(kind, intent, manifest_id, mode))
      end
      # rubocop:enable Metrics/MethodLength

      private

      # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength, Metrics/AbcSize -- private saga steps
      attr_reader :saga_coordinator, :lock_manager, :atomic_mutator, :post_condition_verifier,
                  :compensation_engine, :integration_queue, :blob_store, :compensation_manifest,
                  :clock_epoch_provider, :workspace_root, :hooks, :wal, :fencing_allocator, :ownership_index

      def unknown_kind_reply(manifest_id, kind)
        {
          result: :unknown_intent_kind,
          state: nil,
          manifest_id: manifest_id,
          error: "unknown intent kind: #{kind}"
        }
      end

      def guard_delete_rename_paths_if_applicable(intent, kind)
        return nil unless %w[delete_file rename_file].include?(kind)

        guard_delete_rename_paths(intent, kind)
      end

      def run_after_path_guard(kind, intent, manifest_id, mode)
        stamp = LogicalClock.new(epoch: @clock_epoch_provider.call.to_i)
        scopes = normalize_scopes(intent)
        intent_hash = compute_intent_hash(intent, scopes)
        started = @saga_coordinator.start(manifest_id: manifest_id, intent_hash: intent_hash,
                                          planned_scopes: scopes, metadata: {})
        return terminal_payload(manifest_id, :error, "saga start #{started}") unless started == :reserved

        emit_kernel_hook(:on_saga_start,
                         manifest_id: manifest_id,
                         intent_hash: intent_hash,
                         scopes: scopes,
                         kind: kind)

        lock_outcome = acquire_locks!(manifest_id, scopes)
        return lock_outcome if lock_outcome[:result] == :error

        dispatch_intent_kind(kind, manifest_id, lock_outcome, intent, intent_hash, stamp, mode, kind)
      end

      def dispatch_intent_kind(kind, manifest_id, lock_outcome, intent, intent_hash, stamp, mode, enqueue_kind)
        case kind
        when "atomic_write", "edit_file", "apply_patch"
          materialized = materialize_intent(intent)
          unless materialized[:ok]
            return abort_precondition_failed(manifest_id, lock_outcome[:leases], materialized[:error])
          end

          advance_or_fail(:locked, "locked", manifest_id, lock_outcome[:leases], materialized[:intent], intent_hash,
                          stamp, mode, enqueue_kind: enqueue_kind)
        when "delete_file"
          advance_delete_file(manifest_id, lock_outcome[:leases], intent, intent_hash, stamp, mode,
                              enqueue_kind: enqueue_kind)
        when "rename_file"
          advance_rename_file(manifest_id, lock_outcome[:leases], intent, intent_hash, stamp, mode,
                              enqueue_kind: enqueue_kind)
        end
      end

      def guard_delete_rename_paths(intent, kind)
        guard = Security::ResourceGuard.new(root: @workspace_root)
        paths =
          case kind
          when "delete_file"
            [File.expand_path(intent[:path].to_s, @workspace_root)]
          when "rename_file"
            [
              File.expand_path(intent[:from_path].to_s, @workspace_root),
              File.expand_path(intent[:to_path].to_s, @workspace_root)
            ]
          else
            []
          end
        paths.each { |p| return "path not allowed" unless guard.allow?(p) }
        nil
      end

      def normalize_intent(intent)
        h = intent.transform_keys(&:to_sym)
        h[:post_conditions] = Array(h[:post_conditions])
        h[:scopes] = Array(h[:scopes])
        h[:edits] = h[:edits].map { |e| e.transform_keys(&:to_sym) } if h[:edits]
        h
      end

      def compute_intent_hash(intent, scopes_for_saga)
        kind = intent[:kind].to_s
        scoped = { "scopes" => scopes_for_saga.map(&:to_s) }
        body = case kind
               when "atomic_write"
                 scoped.merge(
                   "kind" => "atomic_write",
                   "path" => intent[:path].to_s,
                   "content_sha" => Digest::SHA256.hexdigest(intent[:content].to_s.b)
                 )
               when "edit_file"
                 scoped.merge(
                   "kind" => "edit_file",
                   "path" => intent[:path].to_s,
                   "edits_digest" => Digest::SHA256.hexdigest(JSON.generate(normalize_edits(intent[:edits])))
                 )
               when "apply_patch"
                 scoped.merge(
                   "kind" => "apply_patch",
                   "path" => intent[:path].to_s,
                   "patch_sha" => Digest::SHA256.hexdigest(intent[:patch].to_s.b)
                 )
               when "delete_file"
                 scoped.merge("kind" => "delete_file", "path" => intent[:path].to_s)
               when "rename_file"
                 scoped.merge(
                   "kind" => "rename_file",
                   "from" => intent[:from_path].to_s,
                   "to" => intent[:to_path].to_s
                 )
               else
                 scoped.merge("kind" => kind)
               end
        Digest::SHA256.hexdigest(JSON.generate(body))
      end

      def normalize_edits(edits)
        Array(edits).map { |e| { "search" => e[:search].to_s, "replace" => e[:replace].to_s } }
      end

      def normalize_scopes(intent)
        intent[:kind].to_s == "rename_file" ? normalize_rename_scopes(intent) : normalize_path_scopes(intent)
      end

      def normalize_rename_scopes(intent)
        f = File.expand_path(intent[:from_path].to_s, @workspace_root)
        t = File.expand_path(intent[:to_path].to_s, @workspace_root)
        list = intent[:scopes]
        scopes =
          if list.nil? || list.empty?
            [f, t]
          else
            list.map { |s| File.expand_path(s.to_s, @workspace_root) }
          end
        scopes.uniq.sort
      end

      def normalize_path_scopes(intent)
        abs_target = File.expand_path(intent[:path].to_s, @workspace_root)
        list = intent[:scopes]
        scopes = list.nil? || list.empty? ? [abs_target] : list.map { |s| File.expand_path(s.to_s, @workspace_root) }
        scopes.uniq.sort
      end

      def materialize_intent(intent)
        kind = intent[:kind].to_s
        path = File.expand_path(intent[:path].to_s, @workspace_root)
        guard = Security::ResourceGuard.new(root: @workspace_root)
        return { ok: false, error: "path not allowed" } unless guard.allow?(path)

        case kind
        when "atomic_write"
          { ok: true, intent: intent }
        when "edit_file"
          materialize_edit_file(intent, path)
        when "apply_patch"
          materialize_apply_patch(intent, path)
        else
          { ok: false, error: "unsupported kind" }
        end
      end

      def materialize_edit_file(intent, path)
        return { ok: false, error: "file must exist for edit_file" } unless File.file?(path)

        bytes = File.binread(path)
        actual = Digest::SHA256.hexdigest(bytes.b)
        return { ok: false, error: "expected_pre_hash mismatch" } unless actual == intent[:expected_pre_hash].to_s

        body = bytes.b.dup
        Array(intent[:edits]).each do |ed|
          search = ed[:search].to_s.b
          repl = ed[:replace].to_s.b
          idx = body.index(search)
          return { ok: false, error: "search not found" } unless idx

          tail = body.bytesize > idx + search.bytesize ? body[(idx + search.bytesize)..] : +""
          body = body[0, idx] + repl + tail
        end

        atomic = intent.merge(kind: "atomic_write", content: body, expected_pre_hash: actual)
        { ok: true, intent: atomic }
      end

      def materialize_apply_patch(intent, path)
        return { ok: false, error: "file must exist for apply_patch" } unless File.file?(path)

        bytes = File.binread(path)
        actual = Digest::SHA256.hexdigest(bytes.b)
        return { ok: false, error: "expected_pre_hash mismatch" } unless actual == intent[:expected_pre_hash].to_s

        status, out = UnifiedDiffApply.apply(bytes.b, intent[:patch].to_s)
        return { ok: false, error: out.to_s } if status != :ok

        atomic = intent.merge(kind: "atomic_write", content: out.b, expected_pre_hash: actual)
        { ok: true, intent: atomic }
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

      def advance_or_fail(state, reason, manifest_id, lease_handles, intent, intent_hash, stamp, mode, enqueue_kind:)
        ok = saga_advance!(manifest_id, state, reason)
        return abort_compensated(manifest_id, lease_handles, "advance #{state} #{ok}") unless ok == :ok

        mutate_verify_and_commit(manifest_id, lease_handles, intent, intent_hash, stamp, mode,
                                 enqueue_kind: enqueue_kind)
      end

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- shadow vs live mutator branch
      def advance_delete_file(manifest_id, lease_handles, intent, intent_hash, stamp, mode, enqueue_kind:)
        ok = saga_advance!(manifest_id, :locked, "locked")
        return abort_compensated(manifest_id, lease_handles, "advance locked #{ok}") unless ok == :ok

        absolute = File.expand_path(intent[:path].to_s, @workspace_root)
        pre = abort_if_disk_prehash_mismatch!(manifest_id, lease_handles, intent[:expected_pre_hash], absolute)
        return pre if pre

        lease = lease_handles.find { |h| h[:scope] == absolute } || lease_handles.last
        comp_op = shadow_execution?(mode) ? "shadow" : "delete"
        record_pre_state!(manifest_id, absolute, lease[:fencing_token], stamp, compensation_op: comp_op)

        del_out =
          if shadow_execution?(mode)
            shadow_wal_delete_file!(intent, intent_hash, manifest_id, stamp, lease[:fencing_token])
          else
            atomic_mutator.delete_file(
              path: intent[:path].to_s,
              mode: mode.to_s,
              fencing_token: lease[:fencing_token],
              expected_pre_hash: intent[:expected_pre_hash],
              intent_hash: intent_hash,
              manifest_id: manifest_id,
              logical_stamp: stamp.next_stamp,
              owner_required: intent[:owner_required],
              supervisor_lease: intent[:supervisor_lease] || false
            )
          end
        return abort_compensated(manifest_id, lease_handles, "mutator #{del_out}") if del_out != :deleted

        verify_commit_tail(manifest_id, lease_handles, stamp, intent, enqueue_kind: enqueue_kind)
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def advance_rename_file(manifest_id, lease_handles, intent, intent_hash, stamp, mode, enqueue_kind:)
        ok = saga_advance!(manifest_id, :locked, "locked")
        return abort_compensated(manifest_id, lease_handles, "advance locked #{ok}") unless ok == :ok

        from_abs = File.expand_path(intent[:from_path].to_s, @workspace_root)
        to_abs = File.expand_path(intent[:to_path].to_s, @workspace_root)
        pre = abort_if_disk_prehash_mismatch!(manifest_id, lease_handles, intent[:expected_pre_hash], from_abs)
        return pre if pre

        lease_from = lease_handles.find { |h| h[:scope] == from_abs }
        lease_to = lease_handles.find { |h| h[:scope] == to_abs }
        record_rename_compensations!(manifest_id, from_abs, to_abs, lease_from, lease_to, stamp, mode)

        ren_out =
          if shadow_execution?(mode)
            shadow_wal_rename_file!(
              intent, intent_hash, manifest_id, stamp,
              lease_from[:fencing_token], lease_to[:fencing_token]
            )
          else
            atomic_mutator.rename_file(
              from_path: intent[:from_path].to_s,
              to_path: intent[:to_path].to_s,
              mode: mode.to_s,
              fencing_token_from: lease_from[:fencing_token],
              fencing_token_to: lease_to[:fencing_token],
              expected_pre_hash_from: intent[:expected_pre_hash],
              intent_hash: intent_hash,
              manifest_id: manifest_id,
              logical_stamp: stamp.next_stamp,
              owner_required: intent[:owner_required],
              supervisor_lease: intent[:supervisor_lease] || false
            )
          end
        return abort_compensated(manifest_id, lease_handles, "mutator #{ren_out}") if ren_out != :renamed

        verify_commit_tail(manifest_id, lease_handles, stamp, intent, enqueue_kind: enqueue_kind)
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def record_rename_compensations!(manifest_id, from_abs, to_abs, lease_from, lease_to, stamp, mode)
        op_restore = shadow_execution?(mode) ? "shadow" : "restore"
        op_unlink = shadow_execution?(mode) ? "shadow" : "unlink"
        ls1 = stamp.next_stamp
        sha = blob_store.put(File.binread(from_abs))
        record_compensation(manifest_id, from_abs, sha, 1, lease_from[:fencing_token], ls1, operation: op_restore)

        ls2 = stamp.next_stamp
        if File.file?(to_abs)
          sha_to = blob_store.put(File.binread(to_abs))
          record_compensation(manifest_id, to_abs, sha_to, 1, lease_to[:fencing_token], ls2, operation: op_restore)
        else
          record_compensation(manifest_id, to_abs, "", 0, lease_to[:fencing_token], ls2, operation: op_unlink)
        end
      end

      def mutate_verify_and_commit(manifest_id, lease_handles, intent, intent_hash, stamp, mode, enqueue_kind:)
        absolute = File.expand_path(intent[:path].to_s, @workspace_root)
        lease = lease_handles.find { |h| h[:scope] == absolute } || lease_handles.last
        comp_op = shadow_execution?(mode) ? "shadow" : "atomic_write"
        record_pre_state!(manifest_id, absolute, lease[:fencing_token], stamp, compensation_op: comp_op)

        write_outcome =
          if shadow_execution?(mode)
            shadow_wal_atomic_write!(intent, intent_hash, manifest_id, stamp, lease[:fencing_token])
          else
            apply_atomic_write(intent, intent_hash, manifest_id, stamp, mode, lease[:fencing_token])
          end
        unless write_outcome == :written
          return abort_compensated(manifest_id, lease_handles, "mutator #{write_outcome}")
        end

        verify_commit_tail(manifest_id, lease_handles, stamp, intent, enqueue_kind: enqueue_kind)
      end

      def verify_commit_tail(manifest_id, lease_handles, stamp, intent, enqueue_kind:)
        ok = saga_advance!(manifest_id, :mutations_applied, "mutations_applied")
        return abort_compensated(manifest_id, lease_handles, "advance mutations_applied #{ok}") unless ok == :ok

        verify_outcome = post_condition_verifier.verify(
          manifest_id: manifest_id,
          checks: intent[:post_conditions],
          logical_stamp: stamp.next_stamp
        )
        return abort_compensated(manifest_id, lease_handles, "post_condition failed") unless verify_outcome[:passed]

        commit_success_path(manifest_id, lease_handles, stamp, enqueue_kind: enqueue_kind)
      end

      def record_pre_state!(manifest_id, absolute, fencing_token, stamp, compensation_op: "atomic_write")
        logical_stamp = stamp.next_stamp
        if File.file?(absolute)
          sha = blob_store.put(File.binread(absolute))
          record_compensation(manifest_id, absolute, sha, 1, fencing_token, logical_stamp, operation: compensation_op)
        else
          record_compensation(manifest_id, absolute, "", 0, fencing_token, logical_stamp, operation: compensation_op)
        end
      end

      def record_compensation(manifest_id, path, sha, pre_existed, fencing_token, logical_stamp,
                              operation: "atomic_write")
        compensation_manifest.record(
          manifest_id: manifest_id,
          path: path,
          op: operation,
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

      def commit_success_path(manifest_id, leases, stamp, enqueue_kind:)
        v = saga_advance!(manifest_id, :verified, "verified")
        return abort_compensated(manifest_id, leases, "advance verified #{v}") unless v == :ok

        q = saga_advance!(manifest_id, :integration_queued, "integration_queued")
        return abort_compensated(manifest_id, leases, "advance integration_queued #{q}") unless q == :ok

        integration_queue.enqueue(
          manifest_id: manifest_id,
          payload: JSON.generate("kind" => enqueue_kind),
          created_at: stamp.next_stamp
        )

        c = saga_advance!(manifest_id, :committed, "committed")
        return abort_compensated(manifest_id, leases, "advance committed #{c}") unless c == :ok

        release_locks(leases)
        snap = saga_coordinator.state_of(manifest_id: manifest_id)
        { result: :ok, state: snap[:state], manifest_id: manifest_id }
      end
      # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength, Metrics/AbcSize

      def abort_precondition_failed(manifest_id, leases, error)
        release_locks(leases)
        emit_kernel_hook(:on_saga_compensate, manifest_id: manifest_id, reason: error.to_s)
        saga_coordinator.compensate(manifest_id: manifest_id, reason: error.to_s)
        snap = saga_coordinator.state_of(manifest_id: manifest_id)
        { result: :precondition_failed, state: snap[:state], manifest_id: manifest_id, error: error.to_s }
      end

      def abort_compensated(manifest_id, leases, reason)
        release_locks(leases)
        epoch = clock_epoch_provider.call.to_s
        emit_kernel_hook(:on_saga_compensate, manifest_id: manifest_id, reason: reason)
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

      def disk_content_pre_hash(absolute)
        return CASGuard::NEW_FILE_SENTINEL unless File.file?(absolute)

        Digest::SHA256.hexdigest(File.binread(absolute).b)
      end

      def abort_if_disk_prehash_mismatch!(manifest_id, leases, expected, absolute)
        return nil if disk_content_pre_hash(absolute) == expected.to_s

        abort_precondition_failed(manifest_id, leases, "expected_pre_hash mismatch")
      end

      def shadow_execution?(mode)
        mode.to_s == ExecutionMode::SHADOW
      end

      def relative_workspace_path(absolute)
        Pathname.new(absolute).relative_path_from(Pathname.new(@workspace_root)).to_s
      end

      def read_path_bytes_or_nil(absolute)
        return nil unless File.file?(absolute)

        File.binread(absolute)
      end

      # rubocop:disable Metrics/CyclomaticComplexity
      def shadow_guard_absolute!(absolute, mode, intent)
        guard = Security::ResourceGuard.new(root: @workspace_root)
        return :forbidden unless guard.allow?(absolute)

        node = ownership_index.lookup(absolute_path: absolute, workspace_root: @workspace_root)
        return :forbidden if node.nil?
        return :forbidden if intent[:owner_required] && node.owner != intent[:owner_required]

        decision = CriticalityPolicy.gate(node, mode: mode.to_s)
        return :forbidden if decision == :reject

        sup = intent[:supervisor_lease]
        return :forbidden if decision == :require_supervisor_lease && !sup

        nil
      end
      # rubocop:enable Metrics/CyclomaticComplexity

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def shadow_wal_atomic_write!(intent, intent_hash, manifest_id, stamp, fencing_token)
        absolute = File.expand_path(intent[:path].to_s, @workspace_root)
        g = shadow_guard_absolute!(absolute, ExecutionMode::SHADOW, intent)
        return g if g

        content = intent[:content].to_s
        prior = read_path_bytes_or_nil(absolute)
        allocated = fencing_allocator.allocate(scope: absolute)
        cas = CASGuard.check(
          current_content_or_nil: prior,
          expected_pre_hash: intent[:expected_pre_hash],
          fencing_token_provided: fencing_token,
          fencing_token_current: allocated
        )
        return cas if cas != :ok

        hex = blob_store.put(content.b)
        payload = JSON.generate(
          "op" => "atomic_write",
          "path" => relative_workspace_path(absolute),
          "bytes" => content.b.bytesize,
          "sha256" => hex
        )
        st = wal.append_mutation(
          manifest_id: manifest_id,
          logical_stamp: stamp.next_stamp,
          payload: payload,
          intent_hash: intent_hash
        )
        return :duplicate if st == :duplicate

        :written
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # rubocop:disable Metrics/MethodLength
      def shadow_wal_delete_file!(intent, intent_hash, manifest_id, stamp, fencing_token)
        absolute = File.expand_path(intent[:path].to_s, @workspace_root)
        g = shadow_guard_absolute!(absolute, ExecutionMode::SHADOW, intent)
        return g if g

        prior = read_path_bytes_or_nil(absolute)
        allocated = fencing_allocator.allocate(scope: absolute)
        cas = CASGuard.check(
          current_content_or_nil: prior,
          expected_pre_hash: intent[:expected_pre_hash],
          fencing_token_provided: fencing_token,
          fencing_token_current: allocated
        )
        return cas if cas != :ok

        payload = JSON.generate("op" => "delete_file", "path" => relative_workspace_path(absolute))
        st = wal.append_mutation(
          manifest_id: manifest_id,
          logical_stamp: stamp.next_stamp,
          payload: payload,
          intent_hash: intent_hash
        )
        return :duplicate if st == :duplicate

        :deleted
      end
      # rubocop:enable Metrics/MethodLength

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists
      def shadow_wal_rename_file!(intent, intent_hash, manifest_id, stamp, fencing_token_from, fencing_token_to)
        from_abs = File.expand_path(intent[:from_path].to_s, @workspace_root)
        to_abs = File.expand_path(intent[:to_path].to_s, @workspace_root)
        g1 = shadow_guard_absolute!(from_abs, ExecutionMode::SHADOW, intent)
        return g1 if g1

        g2 = shadow_guard_absolute!(to_abs, ExecutionMode::SHADOW, intent)
        return g2 if g2

        prior = read_path_bytes_or_nil(from_abs)
        allocated_from = fencing_allocator.allocate(scope: from_abs)
        cas = CASGuard.check(
          current_content_or_nil: prior,
          expected_pre_hash: intent[:expected_pre_hash],
          fencing_token_provided: fencing_token_from,
          fencing_token_current: allocated_from
        )
        return cas if cas != :ok

        allocated_to = fencing_allocator.allocate(scope: to_abs)
        return :stale_token unless CASGuard.fence_allows?(fencing_token_to, allocated_to)

        payload = JSON.generate(
          "op" => "rename_file",
          "from" => relative_workspace_path(from_abs),
          "to" => relative_workspace_path(to_abs)
        )
        st = wal.append_mutation(
          manifest_id: manifest_id,
          logical_stamp: stamp.next_stamp,
          payload: payload,
          intent_hash: intent_hash
        )
        return :duplicate if st == :duplicate

        :renamed
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists

      def emit_kernel_hook(event, **payload)
        return if hooks.nil? || !hooks.respond_to?(:emit)

        hooks.emit(event, payload)
      end

      def emit_pipeline_complete(manifest_id, outcome)
        emit_kernel_hook(
          :on_kernel_pipeline_complete,
          result: outcome[:result],
          manifest_id: manifest_id,
          state: outcome[:state],
          error: outcome[:error]
        )
        outcome
      end

      def saga_advance!(manifest_id, to_state, reason)
        ok = saga_coordinator.advance(manifest_id: manifest_id, to_state: to_state, reason: reason)
        emit_kernel_hook(:on_saga_advance, manifest_id: manifest_id, state: to_state, reason: reason) if ok == :ok
        ok
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

require_relative "kernel_pipeline_assembly"

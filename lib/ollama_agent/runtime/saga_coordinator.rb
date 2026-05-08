# frozen_string_literal: true

require "json"

module OllamaAgent
  module Runtime
    # Durable saga FSM with intent reservation, transition log, and terminal sealing.
    #
    # Callers that hold multiple sagas or locks should follow a consistent global lock/saga order;
    # this class does not reorder resources for you.
    # rubocop:disable Metrics/ClassLength -- FSM + persistence in one unit
    class SagaCoordinator
      START_FROM = "__start__"

      # Raised to unwind {SQLite3::Database#transaction} without treating the outcome as failure.
      class AbortTransaction < StandardError; end

      # rubocop:disable Metrics/ParameterLists -- constructor mirrors kernel wiring (E7/E8)
      def initialize(db:, intent_reservation:, lock_manager:, atomic_mutator:, wal:, clock_epoch_provider:)
        @db = db
        @intent_reservation = intent_reservation
        @lock_manager = lock_manager
        @atomic_mutator = atomic_mutator
        @wal = wal
        @clock_epoch_provider = clock_epoch_provider
      end
      # rubocop:enable Metrics/ParameterLists

      # @return [:reserved, :duplicate, :conflict]
      def start(manifest_id:, intent_hash:, planned_scopes:, supervisor_lease: nil, metadata: {})
        run_tx(:reserved) { perform_start(manifest_id, intent_hash, planned_scopes, supervisor_lease, metadata) }
      end

      # @return [:ok, :illegal_transition, :sealed, :missing]
      def advance(manifest_id:, to_state:, reason: nil)
        run_tx(:ok) { resolve_advance(manifest_id, to_state, reason, next_epoch) }
      end

      # @return [:ok, :sealed, :missing]
      def compensate(manifest_id:, reason:)
        run_tx(:ok) { resolve_compensate(manifest_id, reason, next_epoch) }
      end

      # Snapshot fields for a saga row.
      #
      # @return [Hash, nil] keys include +:state+, +:terminal+, +:intent_hash+, +:planned_scopes+, +:supervisor_lease+
      def state_of(manifest_id:)
        row = @db.get_first_row("SELECT * FROM sagas WHERE manifest_id = ?", [manifest_id])
        return nil unless row

        {
          state: row["state"],
          terminal: row["terminal"].to_i == 1,
          intent_hash: row["intent_hash"],
          planned_scopes: JSON.parse(row["planned_scopes"]),
          supervisor_lease: row["supervisor_lease"]
        }
      end

      # @yieldparam row [Hash{:manifest_id=>String, :state=>String}]
      def each_active
        return enum_for(:each_active) unless block_given?

        @db.execute("SELECT manifest_id, state FROM sagas WHERE terminal = 0 ORDER BY manifest_id") do |r|
          yield({ manifest_id: r["manifest_id"], state: r["state"] })
        end
      end

      private

      attr_reader :lock_manager, :atomic_mutator, :wal

      def run_tx(expected)
        outcome = expected
        @db.transaction(:immediate) do
          outcome = yield
          raise AbortTransaction if outcome != expected
        end
        outcome
      rescue AbortTransaction
        outcome
      end

      def perform_start(manifest_id, intent_hash, planned_scopes, supervisor_lease, metadata)
        epoch = next_epoch
        outcome = reserve_intent(manifest_id, intent_hash, planned_scopes, epoch)
        return outcome unless outcome == :reserved

        persist_started_saga(manifest_id, intent_hash, planned_scopes, supervisor_lease, metadata, epoch)
        :reserved
      end

      def reserve_intent(manifest_id, intent_hash, planned_scopes, epoch)
        @intent_reservation.reserve_joining(
          intent_hash: intent_hash,
          manifest_id: manifest_id,
          scopes: planned_scopes,
          current_epoch: epoch
        )
      end

      # rubocop:disable Metrics/ParameterLists -- start payload maps 1:1 to saga columns
      def persist_started_saga(manifest_id, intent_hash, planned_scopes, supervisor_lease, metadata, epoch)
        insert_new_saga!(manifest_id, intent_hash, planned_scopes, supervisor_lease, metadata, epoch)
        append_transition!(
          manifest_id: manifest_id,
          from_state: START_FROM,
          to_state: "reserved",
          reason: "start",
          epoch: epoch
        )
      end
      # rubocop:enable Metrics/ParameterLists

      def resolve_advance(manifest_id, to_state, reason, epoch)
        row = saga_row(manifest_id)
        return :missing unless row
        return :sealed if row["terminal"].to_i == 1

        try_advance(row, manifest_id, to_state, reason, epoch)
      end

      def try_advance(row, manifest_id, to_state, reason, epoch)
        from = row["state"]
        return :illegal_transition unless SagaState.can_transition?(from, to_state)

        finalize_advance(row, manifest_id, to_state, reason, epoch)
      end

      def finalize_advance(row, manifest_id, to_state, reason, epoch)
        from = row["state"]
        apply_state_change!(row, to_state, epoch)
        append_transition!(
          manifest_id: manifest_id,
          from_state: from,
          to_state: to_state.to_s,
          reason: reason,
          epoch: epoch
        )
        :ok
      end

      def resolve_compensate(manifest_id, reason, epoch)
        row = saga_row(manifest_id)
        return :missing unless row
        return :sealed if row["terminal"].to_i == 1

        try_compensate(row, manifest_id, reason, epoch)
      end

      def try_compensate(row, manifest_id, reason, epoch)
        from = row["state"]
        return :illegal_transition unless SagaState.can_transition?(from, "compensated")

        finalize_compensate(row, manifest_id, from, reason, epoch)
      end

      def finalize_compensate(row, manifest_id, from, reason, epoch)
        apply_state_change!(row, "compensated", epoch)
        @intent_reservation.release_joining(intent_hash: row["intent_hash"], manifest_id: manifest_id)
        append_transition!(
          manifest_id: manifest_id,
          from_state: from,
          to_state: "compensated",
          reason: reason,
          epoch: epoch
        )
        :ok
      end

      def apply_state_change!(row, to_state, epoch)
        terminal = SagaState.terminal?(to_state) ? 1 : 0
        @db.execute(
          "UPDATE sagas SET state = ?, terminal = ?, last_transition_at_epoch = ? WHERE manifest_id = ?",
          [to_state.to_s, terminal, epoch, row["manifest_id"]]
        )
      end

      def saga_row(manifest_id)
        @db.get_first_row("SELECT * FROM sagas WHERE manifest_id = ?", [manifest_id])
      end

      # rubocop:disable Metrics/ParameterLists -- one row insert; fields map 1:1 to schema
      def insert_new_saga!(manifest_id, intent_hash, planned_scopes, supervisor_lease, metadata, epoch)
        scopes_json = JSON.generate(normalize_scopes(planned_scopes))
        meta_json = JSON.generate(metadata || {})
        @db.execute(
          "INSERT INTO sagas (manifest_id, state, intent_hash, planned_scopes, supervisor_lease, " \
          "last_transition_at_epoch, terminal, metadata) VALUES (?,?,?,?,?,?,0,?)",
          [manifest_id, "reserved", intent_hash, scopes_json, supervisor_lease, epoch, meta_json]
        )
      end
      # rubocop:enable Metrics/ParameterLists

      def append_transition!(manifest_id:, from_state:, to_state:, reason:, epoch:)
        @db.execute(
          "INSERT INTO saga_transitions (manifest_id, from_state, to_state, reason, logical_stamp, created_at_epoch) " \
          "VALUES (?,?,?,?,?,?)",
          [manifest_id, from_state, to_state, reason, epoch.to_s, epoch]
        )
      end

      def normalize_scopes(scopes)
        scopes.map(&:to_s).uniq.sort
      end

      def next_epoch
        @clock_epoch_provider.call.to_i
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

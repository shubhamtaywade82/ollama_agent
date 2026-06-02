# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # In-memory rolling-window counters for operator rollback heuristics (no persistence).
    class RollbackSignals
      DEFAULT_THRESHOLDS = {
        replay_determinism_violations_per_min: 1,
        recovery_duplicates_per_min: 1,
        mutation_failure_rate: 0.1,
        validator_integrity_mismatches_per_min: 1
      }.freeze

      WINDOW_TICKS = 60

      VALID_EVENTS = %i[
        replay_determinism_violation
        recovery_duplicate
        mutation_failure
        mutation_success
        validator_integrity_mismatch
      ].freeze

      # @param thresholds [Hash] see DEFAULT_THRESHOLDS keys (Float or Integer)
      def initialize(thresholds: {})
        @thresholds = DEFAULT_THRESHOLDS.merge(thresholds.transform_keys(&:to_sym))
        @current_epoch = 0
        @rows = []
        @mutex = Mutex.new
      end

      # @param event [Symbol] see VALID_EVENTS
      # @param payload [Hash] optional :epoch / "epoch" logical epoch for this sample
      def record(event:, payload: {})
        sym = event.to_sym
        raise ArgumentError, "unknown rollback signal #{sym.inspect}" unless VALID_EVENTS.include?(sym)

        @mutex.synchronize do
          epoch = (payload[:epoch] || payload["epoch"] || @current_epoch).to_i
          @rows << { epoch: epoch, event: sym, ts_wall: Time.now.to_f }
          prune_unlocked!
        end
      end

      # Advance logical epoch and evict samples older than the 60-tick window.
      def tick(epoch:)
        @mutex.synchronize do
          @current_epoch = epoch.to_i
          prune_unlocked!
        end
      end

      # @return [Hash] +:trigger+ (Boolean), +:reasons+ (Array<String>)
      # rubocop:disable Naming/PredicateMethod, Metrics/MethodLength, Metrics/AbcSize -- operator-facing query name + explicit thresholds
      def should_rollback?
        snap = @mutex.synchronize { @rows.dup }
        reasons = []
        t = @thresholds

        reasons << "replay_determinism_violation threshold breached" if count_event(snap, :replay_determinism_violation) >= t[:replay_determinism_violations_per_min]

        reasons << "recovery_duplicate threshold breached" if count_event(snap, :recovery_duplicate) >= t[:recovery_duplicates_per_min]

        reasons << "validator_integrity_mismatch threshold breached" if count_event(snap, :validator_integrity_mismatch) >= t[:validator_integrity_mismatches_per_min]

        mf = count_event(snap, :mutation_failure)
        ms = count_event(snap, :mutation_success)
        total = mf + ms
        reasons << "mutation_failure_rate threshold breached" if total.positive? && (mf.to_f / total) >= t[:mutation_failure_rate].to_f

        { trigger: reasons.any?, reasons: reasons }
      end
      # rubocop:enable Naming/PredicateMethod, Metrics/MethodLength, Metrics/AbcSize

      private

      def prune_unlocked!
        floor = @current_epoch - WINDOW_TICKS
        @rows.reject! { |r| r[:epoch] < floor }
      end

      def count_event(snap, sym)
        snap.count { |r| r[:event] == sym }
      end
    end
  end
end

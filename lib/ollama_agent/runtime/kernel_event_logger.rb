# frozen_string_literal: true

require "json"

module OllamaAgent
  module Runtime
    # Duck-typed hooks subscriber: JSON one-line kernel observability events.
    class KernelEventLogger
      def initialize(logger:, rollback_signals: nil)
        @logger = logger
        @rollback_signals = rollback_signals
      end

      # @param event [Symbol]
      # @param payload [Hash]
      # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
      def emit(event, payload)
        ph = payload.respond_to?(:to_h) ? payload.to_h : {}
        row = {
          ts_epoch: ph[:epoch] || ph["epoch"] || monotonic_epoch,
          event: event.to_s,
          manifest_id: ph[:manifest_id] || ph["manifest_id"],
          state: (ph[:state] || ph["state"])&.to_s,
          result: (ph[:result] || ph["result"])&.to_s,
          error: ph[:error] || ph["error"]&.to_s,
          kind: ph[:kind] || ph["kind"]&.to_s,
          scopes: ph[:scopes] || ph["scopes"],
          reason: ph[:reason] || ph["reason"]&.to_s,
          intent_hash: ph[:intent_hash] || ph["intent_hash"]
        }
        @logger.info(JSON.generate(row.compact))
        forward_rollback(event, ph)
      end
      # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize

      private

      def monotonic_epoch
        Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i
      end

      def forward_rollback(event, payload_hash)
        rs = @rollback_signals
        return unless rs && event.to_sym == :on_kernel_pipeline_complete

        res = payload_hash[:result] || payload_hash["result"]
        sym = res.is_a?(Symbol) ? res : res.to_s.to_sym
        evt = { error: :mutation_failure, ok: :mutation_success }[sym]
        rs.record(event: evt, payload: payload_hash) if evt
      end
    end
  end
end

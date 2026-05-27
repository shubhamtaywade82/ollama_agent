# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # Epoch-gated driver for {Compactor}; safe to call from a daemon loop (not auto-started).
    class CompactorRunner
      def initialize(compactor:, interval_epochs:)
        @compactor = compactor
        @interval = interval_epochs.to_i
        @last_compact_epoch = nil
      end

      # @return [Hash, nil] compaction counts when a run fires; +nil+ when below interval
      def tick(current_epoch:)
        epoch = current_epoch.to_i
        if @last_compact_epoch.nil? || (epoch - @last_compact_epoch) >= @interval
          @last_compact_epoch = epoch
          return @compactor.compact(current_epoch: epoch)
        end

        nil
      end
    end
  end
end

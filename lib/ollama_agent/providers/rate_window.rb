# frozen_string_literal: true

module OllamaAgent
  module Providers
    # Thread-safe sliding-window counter for rate-limit awareness.
    #
    # Tracks how many units (requests or tokens) have occurred within a rolling
    # time window. Used by QuotaTracker to compute live RPM and TPM.
    #
    # @example
    #   window = RateWindow.new(window_seconds: 60)
    #   window.record(1)           # one request
    #   window.record(1500)        # 1500 tokens
    #   window.current_rate        # => sum of values within last 60 s
    class RateWindow
      def initialize(window_seconds: 60)
        @window  = window_seconds.to_i
        @entries = [] # Array of { at: Time, value: Integer }
        @mutex   = Mutex.new
      end

      # Record a value (default 1 for request counting, N for token counting).
      # @param value [Integer]
      def record(value = 1)
        @mutex.synchronize do
          prune!
          @entries << { at: Time.now, value: value.to_i }
        end
      end

      # Sum of all values recorded within the current window.
      # @return [Integer]
      def current_rate
        @mutex.synchronize do
          prune!
          @entries.sum { |e| e[:value] }
        end
      end

      # Number of entries in the current window (for request-count windows).
      # @return [Integer]
      def count
        @mutex.synchronize do
          prune!
          @entries.size
        end
      end

      private

      def prune!
        cutoff = Time.now - @window
        @entries.reject! { |e| e[:at] < cutoff }
      end
    end
  end
end

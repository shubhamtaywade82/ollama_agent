# frozen_string_literal: true

require_relative "rate_window"

module OllamaAgent
  module Providers
    # Per-credential usage accounting against declared provider limits.
    #
    # Tracks daily token/request consumption and live RPM/TPM windows.
    # Since most providers don't expose a real-time quota API, usage is
    # estimated locally from response metadata (prompt_tokens +
    # completion_tokens returned by each successful call).
    #
    # Daily counters auto-reset at midnight UTC.
    #
    # @example
    #   tracker = QuotaTracker.new(limits: { rpm: 60, tpm: 90_000, daily_tokens: 10_000_000 })
    #   tracker.record({ prompt_tokens: 500, completion_tokens: 200, total_tokens: 700 })
    #   tracker.exhausted?          # => false
    #   tracker.near_exhaustion?    # => false
    #   tracker.summary             # => { daily_tokens: 700, rpm: 1, tpm: 700, ... }
    class QuotaTracker
      NEAR_EXHAUSTION_PCT = 0.90

      # @param limits [Hash] declared provider limits:
      #   :rpm            Integer   max requests per minute
      #   :tpm            Integer   max tokens per minute
      #   :daily_tokens   Integer   max tokens per day
      #   :daily_requests Integer   max requests per day
      def initialize(limits: {})
        @limits          = limits.transform_keys(&:to_sym)
        @daily_tokens    = 0
        @daily_requests  = 0
        @daily_reset_at  = next_midnight
        @rpm_window      = RateWindow.new(window_seconds: 60)
        @tpm_window      = RateWindow.new(window_seconds: 60)
        @mutex           = Mutex.new
      end

      # Record usage from a successful response.
      # @param usage [Hash, nil] { prompt_tokens:, completion_tokens:, total_tokens: }
      def record(usage)
        return unless usage

        tokens = (usage[:total_tokens] || usage["total_tokens"] || 0).to_i

        @mutex.synchronize do
          maybe_reset_daily!
          @daily_tokens   += tokens
          @daily_requests += 1
        end

        # Rate windows have their own mutex
        @rpm_window.record(1)
        @tpm_window.record(tokens)
      end

      # True when daily hard limits are hit (requests will be rejected by the provider).
      # @return [Boolean]
      def exhausted?
        @mutex.synchronize do
          maybe_reset_daily!
          daily_token_limit_hit? || daily_request_limit_hit?
        end
      end

      # True when usage is approaching exhaustion (>= 90% of daily token limit).
      # Used for predictive rerouting before a hard failure occurs.
      # @return [Boolean]
      def near_exhaustion?
        @mutex.synchronize do
          maybe_reset_daily!
          daily_pct >= NEAR_EXHAUSTION_PCT
        end
      end

      # Quota utilisation as a fraction [0.0, 1.0] of the daily token limit.
      # Returns 0.0 if no daily token limit is configured.
      # @return [Float]
      def daily_utilisation
        @mutex.synchronize do
          maybe_reset_daily!
          daily_pct
        end
      end

      # Full usage snapshot for TUI and telemetry.
      # @return [Hash]
      def summary
        @mutex.synchronize do
          maybe_reset_daily!
          {
            daily_tokens:        @daily_tokens,
            daily_tokens_limit:  @limits[:daily_tokens],
            daily_requests:      @daily_requests,
            daily_requests_limit: @limits[:daily_requests],
            rpm:                 @rpm_window.current_rate,
            rpm_limit:           @limits[:rpm],
            tpm:                 @tpm_window.current_rate,
            tpm_limit:           @limits[:tpm],
            daily_pct:           daily_pct,
            resets_at:           @daily_reset_at
          }
        end
      end

      private

      # ── helpers ──────────────────────────────────────────────────────────

      def maybe_reset_daily!
        return if Time.now < @daily_reset_at

        @daily_tokens   = 0
        @daily_requests = 0
        @daily_reset_at = next_midnight
      end

      # Next midnight in local time (providers typically reset at midnight UTC
      # or account-anniversary; local midnight is a safe conservative estimate).
      def next_midnight
        t = Time.now
        Time.mktime(t.year, t.month, t.day) + 86_400
      end

      def daily_pct
        lim = @limits[:daily_tokens].to_f
        return 0.0 if lim.zero?

        [@daily_tokens / lim, 1.0].min
      end

      def daily_token_limit_hit?
        lim = @limits[:daily_tokens].to_i
        lim.positive? && @daily_tokens >= lim
      end

      def daily_request_limit_hit?
        lim = @limits[:daily_requests].to_i
        lim.positive? && @daily_requests >= lim
      end
    end
  end
end

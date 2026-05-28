# frozen_string_literal: true

require_relative "quota_tracker"

module OllamaAgent
  module Providers
    # Runtime credential resource.
    #
    # A Credential wraps an API key (and optional base_url for compatible APIs)
    # together with its live health state: failures, cooldowns, quota consumption,
    # and a permanent-disable flag for authentication failures.
    #
    # All mutable state is protected by a Mutex so that the CredentialRouter can
    # safely access credentials from concurrent threads.
    #
    # @example Configuring a credential
    #   cred = OllamaAgent::Providers::Credential.new(
    #     id:       "openai-primary",
    #     provider: "openai",
    #     api_key:  ENV["OPENAI_KEY_1"],
    #     weight:   2,
    #     limits:   { rpm: 60, tpm: 90_000, daily_tokens: 10_000_000 }
    #   )
    #   cred.available?   # => true
    #   cred.mark_failure!(OllamaAgent::RateLimitError.new("429"))
    #   cred.available?   # => false (cooling down)
    class Credential
      # Cooldown durations by error type
      COOLDOWNS = {
        OllamaAgent::QuotaExhaustedError    => 3600,  # 1 h  — daily/monthly limit
        OllamaAgent::RateLimitError         => 60,    # 60 s — RPM/TPM window
        OllamaAgent::TemporaryProviderError => 15     # 15 s — 5xx / timeout
      }.freeze

      DEFAULT_COOLDOWN = 30 # s — unknown errors

      attr_reader :id, :provider, :api_key, :base_url, :weight,
                  :limits, :quota_tracker

      # @param id        [String]  unique name, e.g. "openai-key-1"
      # @param provider  [String]  "openai" | "anthropic" | "ollama" | "groq" | …
      # @param api_key   [String, nil]
      # @param base_url  [String, nil] override for compatible endpoints (Groq, Together, etc.)
      # @param weight    [Integer] relative routing weight (1–100); higher = more traffic
      # @param limits    [Hash]   { rpm:, tpm:, daily_tokens:, daily_requests: }
      # @param name      [String, nil] human-readable label; defaults to id
      def initialize(id:, provider:, api_key: nil, base_url: nil,
                     weight: 1, limits: {}, name: nil)
        @id            = id.to_s
        @provider      = provider.to_s
        @api_key       = api_key
        @base_url      = base_url
        @weight        = weight.to_i.clamp(1, 100)
        @limits        = limits.transform_keys(&:to_sym)
        @display_name  = name || id.to_s
        @quota_tracker = QuotaTracker.new(limits: @limits)

        # ── Mutable health state (Mutex-protected) ──────────────────────
        @mutex          = Mutex.new
        @failures       = 0
        @cooldown_until = nil
        @disabled       = false  # permanent — set on AuthenticationError
        @last_used_at   = nil
      end

      # True when this credential can currently accept a request.
      # @return [Boolean]
      def available?
        @mutex.synchronize { available_unsafe? }
      end

      # True when usage is approaching the daily token limit (>= 90%).
      # Used for predictive rerouting before a hard failure.
      # @return [Boolean]
      def near_exhaustion?
        @quota_tracker.near_exhaustion?
      end

      # Record a failure and apply the appropriate cooldown / permanent disable.
      # @param error [StandardError] ideally a typed OllamaAgent error
      def mark_failure!(error)
        @mutex.synchronize do
          if error.is_a?(OllamaAgent::AuthenticationError)
            @disabled = true  # permanent — bad key, never retry
            return
          end

          @failures += 1
          cooldown_seconds = COOLDOWNS.fetch(error.class, DEFAULT_COOLDOWN)
          @cooldown_until  = Time.now + cooldown_seconds
        end
      end

      # Record a successful response and update quota state.
      # @param usage [Hash, nil] token usage from the response
      def mark_success!(usage: nil)
        @mutex.synchronize do
          @failures       = 0
          @cooldown_until = nil
          @last_used_at   = Time.now
        end
        @quota_tracker.record(usage) if usage
      end

      # Returns remaining cooldown in seconds (0 if not cooling down).
      # @return [Integer]
      def cooldown_remaining
        @mutex.synchronize do
          return 0 unless @cooldown_until && Time.now < @cooldown_until

          (@cooldown_until - Time.now).ceil
        end
      end

      # Full status snapshot for TUI and telemetry.
      # @return [Hash]
      def status_summary
        @mutex.synchronize do
          {
            id:               @id,
            provider:         @provider,
            name:             @display_name,
            available:        available_unsafe?,
            disabled:         @disabled,
            cooling_down:     cooling_down?,
            cooldown_secs:    cooldown_remaining_unsafe,
            failures:         @failures,
            last_used_at:     @last_used_at,
            near_exhaustion:  near_exhaustion?,
            quota:            @quota_tracker.summary
          }
        end
      end

      def to_s
        "#<#{self.class.name} id=#{@id} provider=#{@provider}>"
      end

      private

      def available_unsafe?
        !@disabled && !cooling_down? && !@quota_tracker.exhausted?
      end

      def cooling_down?
        @cooldown_until && Time.now < @cooldown_until
      end

      def cooldown_remaining_unsafe
        return 0 unless @cooldown_until && Time.now < @cooldown_until

        (@cooldown_until - Time.now).ceil
      end
    end
  end
end

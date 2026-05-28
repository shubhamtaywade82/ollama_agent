# frozen_string_literal: true

module OllamaAgent
  module Providers
    # Maps raw HTTP errors and Ruby exceptions into the typed OllamaAgent error
    # hierarchy so that the CredentialRouter can apply the correct cooldown and
    # retry strategy without coupling to provider-specific error messages.
    #
    # Classification rules (in priority order):
    #   HTTP 401 / 403  → AuthenticationError   (permanent disable)
    #   HTTP 402        → QuotaExhaustedError   (long cooldown)
    #   HTTP 429 + quota phrasing → QuotaExhaustedError
    #   HTTP 429 (plain)          → RateLimitError
    #   HTTP 5xx        → TemporaryProviderError (brief cooldown)
    #   Timeout / network → TemporaryProviderError
    #   Unknown           → re-raised as-is
    module ErrorClassifier
      # Phrases that signal a long-term quota exhaustion rather than a short
      # rate-limit window. Matched case-insensitively against error.message.
      QUOTA_PHRASES = %w[
        quota exceeded daily_limit monthly_limit weekly_limit
        billing insufficient_quota run\ out\ of\ credits
        weekly\ usage\ limit monthly\ usage\ limit
        exceeded\ your\ current\ quota
        you\ have\ run\ out
      ].freeze

      module_function

      # Classify a raw error into a typed OllamaAgent error.
      #
      # @param error       [StandardError]
      # @param http_status [Integer, nil]  explicit HTTP status (overrides auto-extract)
      # @return [OllamaAgent::Error] typed error, or the original if unclassifiable
      def classify(error, http_status: nil)
        status = http_status || extract_http_status(error)

        return classify_by_status(status, error) if status && !status.zero?
        return classify_network(error)            if network_error?(error)

        error # pass through — caller should re-raise
      end

      # @param error [StandardError]
      # @return [Boolean]
      def permanently_disabling?(error)
        error.is_a?(OllamaAgent::AuthenticationError)
      end

      # @param error [StandardError]
      # @return [Boolean]
      def retryable_with_other_credential?(error)
        error.is_a?(OllamaAgent::RateLimitError)      ||
          error.is_a?(OllamaAgent::QuotaExhaustedError)  ||
          error.is_a?(OllamaAgent::TemporaryProviderError)
      end

      # @param error [StandardError]
      # @return [Boolean]
      def quota_exhaustion_message?(error)
        quota_phrased?(error.message.to_s)
      end

      private_class_method

      def self.classify_by_status(status, error)
        msg = error.message
        case status
        when 401, 403
          OllamaAgent::AuthenticationError.new(msg)
        when 402
          OllamaAgent::QuotaExhaustedError.new(msg)
        when 429
          quota_phrased?(msg) ?
            OllamaAgent::QuotaExhaustedError.new(msg) :
            OllamaAgent::RateLimitError.new(msg)
        when 500..599
          OllamaAgent::TemporaryProviderError.new(msg)
        else
          error
        end
      end

      def self.classify_network(error)
        OllamaAgent::TemporaryProviderError.new(error.message)
      end

      def self.extract_http_status(error)
        error.message.to_s[/\b(\d{3})\b/, 1].to_i
      end

      def self.quota_phrased?(msg)
        m = msg.to_s.downcase
        QUOTA_PHRASES.any? { |phrase| m.include?(phrase) }
      end

      def self.network_error?(error)
        error.is_a?(Timeout::Error)          ||
          error.is_a?(Errno::ECONNREFUSED)   ||
          error.is_a?(Errno::ECONNRESET)     ||
          error.is_a?(Errno::ETIMEDOUT)      ||
          (defined?(SocketError) && error.is_a?(SocketError))
      end
    end
  end
end

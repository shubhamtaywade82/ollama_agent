# frozen_string_literal: true

require "timeout"
require_relative "retry_policy"

module OllamaAgent
  module Resilience
    # Wraps an Ollama::Client with exponential backoff retry for transient errors.
    class RetryMiddleware
      DEFAULT_MAX_ATTEMPTS = RetryPolicy::DEFAULT_MAX_ATTEMPTS
      DEFAULT_BASE_DELAY   = RetryPolicy::DEFAULT_BASE_DELAY

      def initialize(client:, max_attempts: DEFAULT_MAX_ATTEMPTS, hooks: nil, base_delay: DEFAULT_BASE_DELAY)
        @client  = client
        @hooks   = hooks
        @policy  = RetryPolicy.new(max_attempts: max_attempts, base_delay: base_delay)
      end

      # rubocop:disable Metrics/MethodLength -- single rescue/retry loop
      def chat(**args)
        attempt = 0
        begin
          @client.chat(**args)
        rescue *RetryPolicy::RETRYABLE => e
          raise if http_error_non_retryable?(e)

          attempt += 1
          raise if attempt >= @policy.max_attempts

          delay = @policy.backoff(attempt)
          @hooks&.emit(:on_retry, { error: e, attempt: attempt, delay_ms: (delay * 1000).round })
          sleep delay
          retry
        end
      end
      # rubocop:enable Metrics/MethodLength

      private

      def http_error_non_retryable?(error)
        error.is_a?(Ollama::HTTPError) && !@policy.retryable_http_error?(error)
      end
    end
  end
end

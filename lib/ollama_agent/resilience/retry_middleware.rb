# frozen_string_literal: true

require "timeout"

module OllamaAgent
  module Resilience
    # Wraps an Ollama::Client with exponential backoff retry for transient errors.
    class RetryMiddleware
      DEFAULT_MAX_ATTEMPTS = 3
      DEFAULT_BASE_DELAY   = 2.0

      RETRYABLE = begin
        [Ollama::TimeoutError, Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET]
      rescue NameError
        [Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET]
      end.freeze

      def initialize(client:, max_attempts: DEFAULT_MAX_ATTEMPTS, hooks: nil, base_delay: DEFAULT_BASE_DELAY)
        @client       = client
        @max_attempts = max_attempts.to_i
        @hooks        = hooks
        @base_delay   = base_delay.to_f
      end

      # rubocop:disable Metrics/MethodLength -- retry loop with backoff needs multiple steps
      def chat(**args)
        attempt = 0
        begin
          @client.chat(**args)
        rescue *RETRYABLE => e
          attempt += 1
          raise if attempt >= @max_attempts

          delay = backoff(attempt)
          @hooks&.emit(:on_retry, { error: e, attempt: attempt, delay_ms: (delay * 1000).round })
          sleep delay
          retry
        end
      end
      # rubocop:enable Metrics/MethodLength

      private

      def backoff(attempt)
        jitter = @base_delay.positive? ? rand * 0.5 : 0
        [(@base_delay * (2**(attempt - 1))) + jitter, 30.0].min
      end
    end
  end
end

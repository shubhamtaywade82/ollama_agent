# frozen_string_literal: true

require "timeout"

module OllamaAgent
  module Resilience
    # Wraps an Ollama::Client with exponential backoff retry for transient errors.
    class RetryMiddleware
      DEFAULT_MAX_ATTEMPTS = 3
      DEFAULT_BASE_DELAY   = 2.0

      RETRYABLE = begin
        list = [Ollama::TimeoutError, Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET]
        # SocketError is not always loaded, but net/http usually loads it.
        # Adding SocketError for DNS/resolution transient issues.
        list << SocketError if defined?(SocketError)
        # Socket::ResolutionError is in Ruby 3.3+
        list << Socket::ResolutionError if defined?(Socket) && defined?(Socket::ResolutionError)
        # Ollama::Error is often raised by the client for connection failures.
        list << Ollama::Error if defined?(Ollama::Error)
        # Ollama::HTTPError for 429/5xx transient issues.
        list << Ollama::HTTPError if defined?(Ollama::HTTPError)
        list
      rescue NameError
        [Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET]
      end.freeze

      def initialize(client:, max_attempts: DEFAULT_MAX_ATTEMPTS, hooks: nil, base_delay: DEFAULT_BASE_DELAY)
        @client       = client
        @max_attempts = max_attempts.to_i
        @hooks        = hooks
        @base_delay   = base_delay.to_f
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- retry loop with backoff and http filtering
      def chat(**args)
        attempt = 0
        begin
          @client.chat(**args)
        rescue *RETRYABLE => e
          raise if e.is_a?(Ollama::HTTPError) && !retryable_http_error?(e)

          attempt += 1
          raise if attempt >= @max_attempts

          delay = backoff(attempt)
          @hooks&.emit(:on_retry, { error: e, attempt: attempt, delay_ms: (delay * 1000).round })
          sleep delay
          retry
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      private

      def retryable_http_error?(error)
        msg = error.message.to_s
        status = msg[/HTTP (\d+)/, 1].to_i
        return false if status.zero?

        # 429 is retryable unless it explicitly says "weekly usage limit" or similar "hard" limits
        if status == 429
          return false if msg.downcase.include?("weekly usage limit")
          return false if msg.downcase.include?("monthly usage limit")

          return true
        end

        # 5xx are generally retryable
        status >= 500 && status <= 599
      end

      def backoff(attempt)
        jitter = @base_delay.positive? ? rand * 0.5 : 0
        [(@base_delay * (2**(attempt - 1))) + jitter, 30.0].min
      end
    end
  end
end

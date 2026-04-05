# frozen_string_literal: true

require "timeout"

module OllamaAgent
  module Resilience
    # Retryable exception list and HTTP status / backoff rules for {RetryMiddleware}.
    class RetryPolicy
      DEFAULT_MAX_ATTEMPTS = 3
      DEFAULT_BASE_DELAY   = 2.0

      RETRYABLE = begin
        list = [Ollama::TimeoutError, Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET]
        list << SocketError if defined?(SocketError)
        list << Socket::ResolutionError if defined?(Socket::ResolutionError)
        list << Ollama::Error if defined?(Ollama::Error)
        list << Ollama::HTTPError if defined?(Ollama::HTTPError)
        list
      rescue NameError
        [Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET]
      end.freeze

      attr_reader :max_attempts, :base_delay

      def initialize(max_attempts: DEFAULT_MAX_ATTEMPTS, base_delay: DEFAULT_BASE_DELAY)
        @max_attempts = max_attempts.to_i
        @base_delay   = base_delay.to_f
      end

      def retryable_http_error?(error)
        msg = error.message.to_s
        status = msg[/HTTP (\d+)/, 1].to_i
        return false if status.zero?

        if status == 429
          return false if msg.downcase.include?("weekly usage limit")
          return false if msg.downcase.include?("monthly usage limit")

          return true
        end

        status.between?(500, 599)
      end

      def backoff(attempt)
        jitter = @base_delay.positive? ? rand * 0.5 : 0
        [(@base_delay * (2**(attempt - 1))) + jitter, 30.0].min
      end
    end
  end
end

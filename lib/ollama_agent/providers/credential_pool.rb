# frozen_string_literal: true

require_relative "credential"

module OllamaAgent
  module Providers
    # Thread-safe pool of Credential objects with weighted round-robin selection.
    #
    # The pool is the single source of truth for which credentials are available.
    # It exposes:
    #   - next_credential  — picks the next available credential (weighted RR)
    #   - any_available?   — fast availability check used by CredentialRouter
    #   - all_status       — full snapshot for TUI and telemetry
    #
    # @example
    #   pool = CredentialPool.new(credentials: [cred_a, cred_b, cred_c])
    #   cred = pool.next_credential   # weighted round-robin
    #   pool.any_available?           # => true / false
    class CredentialPool
      def initialize(credentials:)
        @credentials = Array(credentials)
        @mutex       = Mutex.new
        @index       = 0
      end

      # Pick the next available credential using weighted round-robin.
      #
      # Weighted RR: each credential is repeated `weight` times in the
      # selection array. A credential with weight=2 receives roughly twice
      # the traffic of one with weight=1.
      #
      # @raise [OllamaAgent::NoAvailableCredentialError] when pool is exhausted
      # @return [Credential]
      def next_credential
        @mutex.synchronize do
          available = @credentials.select(&:available?)

          if available.empty?
            names = @credentials.map(&:id).join(", ")
            raise OllamaAgent::NoAvailableCredentialError,
                  "All credentials exhausted or cooling down (pool: #{names})"
          end

          # Expand by weight so each slot in the array represents one "share"
          weighted = available.flat_map { |c| Array.new(c.weight, c) }
          cred     = weighted[@index % weighted.size]
          @index   = (@index + 1) % weighted.size
          cred
        end
      end

      # @return [Boolean]
      def any_available?
        @credentials.any?(&:available?)
      end

      # @return [Array<String>] ids of credentials approaching quota exhaustion
      def near_exhaustion_ids
        @credentials.select(&:near_exhaustion?).map(&:id)
      end

      # @return [Integer]
      def size
        @credentials.size
      end

      # Full status snapshot for the TUI providers panel.
      # @return [Array<Hash>]
      def all_status
        @credentials.map(&:status_summary)
      end

      # Aggregate quota summary across all credentials for the same provider.
      # Useful for the "Usage" TUI panel.
      # @return [Hash]
      def aggregate_usage
        all = @credentials.map { |c| c.quota_tracker.summary }
        {
          total_daily_tokens: all.sum { |s| s[:daily_tokens] },
          total_daily_requests: all.sum { |s| s[:daily_requests] },
          total_rpm: all.sum { |s| s[:rpm] },
          total_tpm: all.sum { |s| s[:tpm] }
        }
      end

      # Find the first available API key for a given provider.
      # @param provider [String]
      # @return [String, nil]
      def first_available_key(provider)
        @mutex.synchronize do
          @credentials.find { |c| c.provider == provider.to_s && c.available? }&.api_key
        end
      end
    end
  end
end

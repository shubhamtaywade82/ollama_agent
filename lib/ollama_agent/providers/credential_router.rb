# frozen_string_literal: true

require_relative "credential_pool"
require_relative "error_classifier"
require_relative "health_monitor"

module OllamaAgent
  module Providers
    # Quota-aware failover dispatcher.
    #
    # Picks credentials from a CredentialPool, builds the matching provider
    # client via a provider_builder lambda, executes the chat call, and handles
    # typed errors by marking the credential and retrying with the next one.
    #
    # This is where reactive failover lives:
    #   1. Pick next available credential (pool decides, weighted RR)
    #   2. Build a transient provider client for that credential
    #   3. Execute #chat
    #   4a. On success → mark credential healthy, record usage, return response
    #   4b. On AuthenticationError → permanently disable credential, STOP (don't retry)
    #   4c. On quota/rate/temp error → mark cooldown, try next credential
    #   5. Raise NoAvailableCredentialError when all attempts exhausted
    #
    # Composes cleanly with the existing Providers::Router — the Router chooses
    # between provider types (OpenAI vs Groq vs Ollama), while the
    # CredentialRouter handles multiple keys for a single provider type.
    #
    # @example
    #   pool    = CredentialPool.new(credentials: [cred_a, cred_b])
    #   builder = ->(cred) { Providers::OpenAI.new(api_key: cred.api_key) }
    #   router  = CredentialRouter.new(pool: pool, provider_builder: builder)
    #   response = router.chat(messages: [...], model: "gpt-4o")
    class CredentialRouter
      MAX_ATTEMPTS = 5

      def initialize(pool:, provider_builder:, health_monitor: nil)
        @pool             = pool
        @provider_builder = provider_builder
        @health_monitor   = health_monitor || HealthMonitor.new
      end

      # Execute a chat request with automatic failover across credentials.
      #
      # @param args [Hash] forwarded to provider#chat (messages:, model:, …)
      # @return [Base::Response]
      # @raise [OllamaAgent::NoAvailableCredentialError] when all attempts fail
      # @raise [OllamaAgent::AuthenticationError]        when a key is invalid
      # rubocop:disable Metrics/MethodLength -- failover loop requires full visibility
      def chat(**args)
        attempts  = 0
        last_cred = nil

        loop do
          if attempts >= MAX_ATTEMPTS
            raise OllamaAgent::NoAvailableCredentialError,
                  "All #{MAX_ATTEMPTS} credential attempts failed"
          end

          credential = @pool.next_credential
          provider   = @provider_builder.call(credential)
          started_at = Time.now

          begin
            response = provider.chat(**args)
            latency  = ((Time.now - started_at) * 1000).round

            credential.mark_success!(usage: response.usage)
            @health_monitor.record_success(credential, latency_ms: latency)

            return response

          rescue OllamaAgent::Error, StandardError => raw_error
            typed = ErrorClassifier.classify(raw_error)
            credential.mark_failure!(typed)
            @health_monitor.record_failure(credential, typed)

            # AuthenticationError → permanent disable, bubble up immediately
            raise typed if typed.is_a?(OllamaAgent::AuthenticationError)

            if last_cred && last_cred != credential
              @health_monitor.record_switch(last_cred, credential, typed.class.name)
            end

            # If not retryable with another credential, bubble up
            raise typed unless ErrorClassifier.retryable_with_other_credential?(typed)

            last_cred = credential
            attempts += 1
            # Loop continues — picks next credential from pool
          end
        end
      end
      # rubocop:enable Metrics/MethodLength

      # @return [Boolean]
      def available?
        @pool.any_available?
      end

      # Full pool status snapshot for TUI.
      # @return [Array<Hash>]
      def pool_status
        @pool.all_status
      end

      # Aggregate usage across all credentials.
      # @return [Hash]
      def aggregate_usage
        @pool.aggregate_usage
      end

      # Recent routing decisions for the TUI decisions panel.
      # @param n [Integer]
      # @return [Array<String>]
      def routing_decisions(n = 10)
        @health_monitor.routing_decisions(n)
      end

      # Ids of near-exhaustion credentials for warnings.
      # @return [Array<String>]
      def near_exhaustion_warnings
        @pool.near_exhaustion_ids
      end

      # Find the first available API key for a given provider in the pool.
      # @param provider [String]
      # @return [String, nil]
      def first_available_key(provider)
        @pool.respond_to?(:first_available_key) ? @pool.first_available_key(provider) : nil
      end
    end
  end
end

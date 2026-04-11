# frozen_string_literal: true

require_relative "base"

module OllamaAgent
  module Providers
    # Routes chat requests to the first available provider.
    # Falls back through the list on errors or unavailability.
    #
    # @example
    #   router = OllamaAgent::Providers::Router.new(
    #     providers: [
    #       OllamaAgent::Providers::Ollama.new,
    #       OllamaAgent::Providers::OpenAI.new(api_key: ENV["OPENAI_API_KEY"])
    #     ],
    #     strategy: :first_available   # or :round_robin, :cheapest
    #   )
    class Router < Base
      STRATEGIES = %i[first_available round_robin cheapest].freeze

      ProviderUnavailableError = Class.new(defined?(OllamaAgent::Error) ? OllamaAgent::Error : StandardError)

      def initialize(providers:, strategy: :first_available, on_fallback: nil, **opts)
        super(name: "router", **opts)
        @providers  = Array(providers)
        @strategy   = STRATEGIES.include?(strategy.to_sym) ? strategy.to_sym : :first_available
        @on_fallback = on_fallback   # optional: lambda(from, to, reason)
        @rr_index   = 0
      end

      def chat(messages:, model:, **kwargs)
        candidates = ordered_providers
        last_error = nil

        candidates.each do |provider|
          next unless provider.available?

          return provider.chat(messages: messages, model: model, **kwargs)
        rescue OllamaAgent::Error, StandardError => e
          last_error = e
          next_provider = candidates[candidates.index(provider).to_i + 1]
          if next_provider
            @on_fallback&.call(provider.name, next_provider.name, e.message)
          end
          next
        end

        raise ProviderUnavailableError, build_unavailable_message(last_error)
      end

      def available?
        @providers.any?(&:available?)
      end

      def available_providers
        @providers.select(&:available?)
      end

      def provider_status
        @providers.map do |p|
          { name: p.name, available: p.available?, streaming: p.streaming_supported? }
        end
      end

      private

      def ordered_providers
        case @strategy
        when :round_robin    then round_robin_order
        when :cheapest       then cheapest_order
        else                      @providers.dup  # first_available
        end
      end

      def round_robin_order
        n = @providers.size
        @rr_index = (@rr_index + 1) % n
        @providers.rotate(@rr_index)
      end

      def cheapest_order
        # Sort by estimated cost per token (use a probe call with 0 tokens as proxy)
        @providers.sort_by { |p| p.estimate_cost(input_tokens: 1000, output_tokens: 500) }
      end

      def build_unavailable_message(last_error)
        names = @providers.map(&:name).join(", ")
        base  = "No providers available (tried: #{names})"
        last_error ? "#{base}. Last error: #{last_error.message}" : base
      end
    end
  end
end

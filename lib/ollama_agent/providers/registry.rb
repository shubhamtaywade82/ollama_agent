# frozen_string_literal: true

require_relative "base"
require_relative "ollama"
require_relative "openai"
require_relative "anthropic"
require_relative "router"

module OllamaAgent
  module Providers
    # Central registry for model providers.
    # Resolves a provider by name string or symbol and builds the Router.
    #
    # @example
    #   provider = OllamaAgent::Providers::Registry.resolve("openai")
    #   OllamaAgent::Providers::Registry.register("my_provider", MyProvider)
    module Registry
      BUILT_IN = {
        "ollama" => Ollama,
        "openai" => OpenAI,
        "anthropic" => Anthropic
      }.freeze

      @custom = {}

      class << self
        # Register a custom provider class.
        def register(name, klass)
          raise ArgumentError, "#{klass} must inherit from Providers::Base" unless klass <= Base

          @custom[name.to_s] = klass
        end

        # Resolve a provider instance by name.
        # @param name [String, Symbol]  provider name or "auto"
        # @param opts [Hash]            forwarded to the provider constructor
        # @return [Base] provider instance
        def resolve(name, **)
          return auto_provider(**) if name.to_s == "auto"

          klass = @custom[name.to_s] || BUILT_IN[name.to_s]
          raise ArgumentError, "Unknown provider: #{name}. Known: #{known_names.join(", ")}" unless klass

          klass.new(**)
        end

        # Build a router from a priority list of provider names.
        # @param names [Array<String>]  provider names in fallback order
        def router(names, strategy: :first_available, **shared_opts)
          providers = names.map { |n| resolve(n, **shared_opts) }
          Router.new(providers: providers, strategy: strategy)
        end

        # Returns a provider that is available right now.
        # Checks Ollama first (free/local), then OpenAI, then Anthropic.
        def auto_provider(**)
          candidates = [
            BUILT_IN["ollama"].new(**),
            (BUILT_IN["openai"].new(**)    if ENV["OPENAI_API_KEY"]),
            (BUILT_IN["anthropic"].new(**) if ENV["ANTHROPIC_API_KEY"])
          ].compact

          Router.new(providers: candidates, strategy: :first_available)
        end

        def known_names
          (BUILT_IN.keys + @custom.keys).uniq
        end

        def reset_custom!
          @custom = {}
        end
      end
    end
  end
end

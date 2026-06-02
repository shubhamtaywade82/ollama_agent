# frozen_string_literal: true

require_relative "base"
require_relative "ollama"
require_relative "openai"
require_relative "anthropic"
require_relative "router"
require_relative "rate_window"
require_relative "quota_tracker"
require_relative "credential"
require_relative "error_classifier"
require_relative "credential_pool"
require_relative "health_monitor"
require_relative "credential_router"
require_relative "model_descriptor"
require_relative "model_registry"

module OllamaAgent
  module Providers
    # Central registry for model providers.
    # Resolves a provider by name string or symbol and builds the Router.
    # Also builds CredentialRouter instances from a credentials config array.
    #
    # @example Single-provider usage (unchanged)
    #   provider = OllamaAgent::Providers::Registry.resolve("openai")
    #
    # @example Multi-credential pool
    #   router = OllamaAgent::Providers::Registry.from_credentials([
    #     { id: "key-1", provider: "openai", api_key: ENV["OPENAI_KEY_1"], weight: 2,
    #       limits: { rpm: 60, tpm: 90_000, daily_tokens: 10_000_000 } },
    #     { id: "key-2", provider: "openai", api_key: ENV["OPENAI_KEY_2"], weight: 1 },
    #     { id: "groq",  provider: "groq",   api_key: ENV["GROQ_KEY"],
    #       base_url: "https://api.groq.com/openai/v1" }
    #   ])
    module Registry
      BUILT_IN = {
        "ollama" => Ollama,
        "ollama_cloud" => Ollama,
        "openai" => OpenAI,
        "anthropic" => Anthropic,
        # OpenAI-compatible aliases — use openai provider with custom base_url
        "groq" => OpenAI,
        "together" => OpenAI,
        "openrouter" => OpenAI
      }.freeze

      # Default base URLs for external providers
      COMPATIBLE_URLS = {
        "groq" => "https://api.groq.com/openai/v1",
        "together" => "https://api.together.xyz/v1",
        "openrouter" => "https://openrouter.ai/api/v1",
        "ollama_cloud" => "https://api.ollama.com"
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
        def resolve(name, **opts)
          return auto_provider(**opts) if name.to_s == "auto"

          n     = name.to_s
          klass = @custom[n] || BUILT_IN[n]
          raise ArgumentError, "Unknown provider: #{name}. Known: #{known_names.join(", ")}" unless klass

          # Inject default base_url for OpenAI-compatible aliases
          opts[:base_url] ||= COMPATIBLE_URLS[n] if COMPATIBLE_URLS.key?(n)

          klass.new(**opts)
        end

        # Build a router from a priority list of provider names.
        # @param names [Array<String>]  provider names in fallback order
        def router(names, strategy: :first_available, **shared_opts)
          providers = names.map { |n| resolve(n, **shared_opts) }
          Router.new(providers: providers, strategy: strategy)
        end

        # Build a CredentialRouter from an array of credential configuration hashes.
        # This is the primary entry point for multi-key / multi-provider setups.
        #
        # @param credentials [Array<Hash>] each hash:
        #   :id        [String]  (required) unique name
        #   :provider  [String]  (required) "openai" | "anthropic" | "groq" | "ollama" | …
        #   :api_key   [String]
        #   :base_url  [String]  override for OpenAI-compatible endpoints
        #   :weight    [Integer] routing weight (default 1)
        #   :limits    [Hash]    { rpm:, tpm:, daily_tokens:, daily_requests: }
        # @param hooks [Streaming::Hooks, nil]
        # @return [CredentialRouter]
        def from_credentials(credentials, hooks: nil)
          creds = credentials.map { |cfg| build_credential(cfg) }
          pool  = CredentialPool.new(credentials: creds)
          mon   = HealthMonitor.new(hooks: hooks)

          CredentialRouter.new(
            pool: pool,
            provider_builder: method(:build_provider_for_credential),
            health_monitor: mon
          )
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

        private

        def build_credential(cfg)
          cfg = cfg.transform_keys(&:to_sym)
          Credential.new(
            id: cfg.fetch(:id),
            provider: cfg.fetch(:provider),
            api_key: cfg[:api_key],
            base_url: cfg[:base_url] || COMPATIBLE_URLS[cfg[:provider].to_s],
            weight: cfg.fetch(:weight, 1),
            limits: cfg.fetch(:limits, {}),
            name: cfg[:name]
          )
        end

        def build_provider_for_credential(credential)
          n     = credential.provider.to_s
          klass = @custom[n] || BUILT_IN[n]
          raise ArgumentError, "Unknown provider for credential #{credential.id}: #{n}" unless klass

          opts = {}
          opts[:api_key]  = credential.api_key  if credential.api_key
          opts[:base_url] = credential.base_url if credential.base_url

          klass.new(name: "#{n}/#{credential.id}", **opts)
        end
      end
    end
  end
end

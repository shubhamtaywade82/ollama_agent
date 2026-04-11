# frozen_string_literal: true

require_relative "model_env"

module OllamaAgent
  # Maps OLLAMA_BASE_URL / OLLAMA_API_KEY / chat model ENV into Ollama::Config (local vs Ollama Cloud).
  module OllamaConnection
    def self.apply_env_to_config(config)
      url = ENV.fetch("OLLAMA_BASE_URL", nil)
      config.base_url = url if url && !url.strip.empty?

      key = ENV.fetch("OLLAMA_API_KEY", nil)
      config.api_key = key if key && !key.strip.empty?

      model = ModelEnv.resolved_model_from_env
      config.model = model if model
    end

    # Builds an +Ollama::Client+ wrapped in {Resilience::RetryMiddleware}.
    #
    # @param timeout [Numeric] read/open timeout seconds
    # @param max_attempts [Integer] retry attempts for the middleware
    # @param base_url [String, nil] optional explicit API base URL (e.g. from +OLLAMA_HOST+); +nil+ keeps config default
    # @param hooks [Streaming::Hooks, nil] optional hooks for retry events
    # @param base_delay [Float, nil] backoff base; default from {Resilience::RetryMiddleware}
    # @return [Resilience::RetryMiddleware]
    def self.retry_wrapped_client(timeout:, max_attempts:, base_url: nil, hooks: nil, base_delay: nil)
      require "ollama_client"
      require_relative "resilience/retry_middleware"

      inner = Ollama::Client.new(config: config_for_client(base_url: base_url, timeout: timeout))
      Resilience::RetryMiddleware.new(
        client: inner,
        max_attempts: max_attempts,
        hooks: hooks,
        base_delay: base_delay || Resilience::RetryMiddleware::DEFAULT_BASE_DELAY
      )
    end

    def self.config_for_client(base_url:, timeout:)
      config = Ollama::Config.new
      config.base_url = base_url if base_url && !base_url.to_s.strip.empty?
      config.timeout = timeout
      apply_env_to_config(config)
      config
    end
    private_class_method :config_for_client
  end
end

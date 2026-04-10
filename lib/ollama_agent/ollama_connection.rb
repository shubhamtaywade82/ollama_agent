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
  end
end

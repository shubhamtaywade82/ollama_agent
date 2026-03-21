# frozen_string_literal: true

module OllamaAgent
  # Maps OLLAMA_BASE_URL / OLLAMA_API_KEY into Ollama::Config (ollama-client convention for local vs cloud).
  module OllamaConnection
    def self.apply_env_to_config(config)
      url = ENV.fetch("OLLAMA_BASE_URL", nil)
      config.base_url = url if url && !url.strip.empty?

      key = ENV.fetch("OLLAMA_API_KEY", nil)
      config.api_key = key if key && !key.strip.empty?
    end
  end
end

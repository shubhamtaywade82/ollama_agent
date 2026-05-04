# frozen_string_literal: true

require_relative "../providers/registry"

module OllamaAgent
  module Skills
    # Thin facade over Providers::Registry tuned for deterministic, single-shot
    # JSON generation. Defaults to the local Ollama provider so skills stay
    # local-first and auditable. Inject any object responding to +#generate+
    # in tests.
    class LlmClient
      DEFAULT_TEMPERATURE = 0.0
      DEFAULT_PROVIDER    = "ollama"

      def initialize(provider: nil, model: nil, temperature: DEFAULT_TEMPERATURE)
        @provider    = provider || Providers::Registry.resolve(DEFAULT_PROVIDER)
        @model       = model || ENV.fetch("OLLAMA_AGENT_SKILL_MODEL", default_model)
        @temperature = temperature
      end

      # @param prompt [String]
      # @return [String] raw assistant content
      def generate(prompt)
        response = @provider.chat(messages: [user_message(prompt)], model: @model, temperature: @temperature)
        content  = response.content
        raise OllamaAgent::Error, "empty response from provider" if content.to_s.strip.empty?

        content
      end

      private

      def user_message(prompt)
        { role: "user", content: prompt }
      end

      def default_model
        ENV.fetch("OLLAMA_AGENT_MODEL", "llama3.2")
      end
    end
  end
end

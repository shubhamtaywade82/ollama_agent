# frozen_string_literal: true

require "ollama_client"

module OllamaAgent
  # Resolves the default chat model from the environment (after global dotenv reconciliation,
  # these values come from ~/.config/ollama_agent/.env or the shell, not the project tree).
  module ModelEnv
    module_function

    # @return [String, nil] model id from ENV when set (used to sync +Ollama::Config+ for Ollama Cloud).
    def resolved_model_from_env
      %w[OLLAMA_AGENT_MODEL OLLAMA_MODEL].each do |name|
        value = ENV[name].to_s.strip
        return value unless value.empty?
      end

      nil
    end

    # @return [String] model id from ENV or ollama-client default (+Ollama::Config.new.model+).
    def default_chat_model
      resolved_model_from_env || Ollama::Config.new.model
    end
  end
end

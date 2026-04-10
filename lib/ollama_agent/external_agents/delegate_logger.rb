# frozen_string_literal: true

require "json"

require_relative "env_helpers"

module OllamaAgent
  module ExternalAgents
    # STDERR logging for delegate runs and shared debug lines (namespaced to avoid Ruby's ::Logger).
    module DelegateLogger
      class << self
        def log_delegate_event(payload)
          return unless delegate_log_enabled?

          warn("ollama_agent_delegate: #{JSON.generate(payload)}")
        rescue StandardError
          nil
        end

        def debug(message)
          warn("ollama_agent: #{message}") if EnvHelpers.env_bool?("OLLAMA_AGENT_DEBUG", default: false)
        end

        def delegate_log_enabled?
          EnvHelpers.env_bool?("OLLAMA_AGENT_DELEGATE_LOG", default: false) ||
            EnvHelpers.env_bool?("OLLAMA_AGENT_DEBUG", default: false)
        end
      end
    end
  end
end

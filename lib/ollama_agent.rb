# frozen_string_literal: true

require_relative "ollama_agent/version"
require "ollama_client"
require_relative "ollama_agent/agent"
require_relative "ollama_agent/cli"

module OllamaAgent
  class Error < StandardError; end
end

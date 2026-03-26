# frozen_string_literal: true

require_relative "ollama_agent/version"
require "ollama_client"
require_relative "ollama_agent/console"
require_relative "ollama_agent/tools/registry"
require_relative "ollama_agent/streaming/hooks"
require_relative "ollama_agent/streaming/console_streamer"
require_relative "ollama_agent/agent"
require_relative "ollama_agent/cli"

# Public namespace for the Ollama-backed coding agent gem (CLI, Agent, tools, self-improvement helpers).
module OllamaAgent
  class Error < StandardError; end

  def self.gem_root
    File.expand_path("..", __dir__)
  end
end

require_relative "ollama_agent/self_improvement"

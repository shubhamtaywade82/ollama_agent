# frozen_string_literal: true

require "thor"

require_relative "agent"

module OllamaAgent
  # Thor CLI for single-shot and interactive agent sessions.
  class CLI < Thor
    desc "ask [QUERY]", "Run a natural-language task (reads, search, patch)"
    method_option :model, type: :string, desc: "Ollama model (default: OLLAMA_AGENT_MODEL or ollama-client default)"
    method_option :interactive, type: :boolean, aliases: "-i", desc: "Interactive REPL"
    method_option :yes, type: :boolean, aliases: "-y", desc: "Apply patches without confirmation"
    method_option :root, type: :string, desc: "Project root (default: OLLAMA_AGENT_ROOT or cwd)"
    method_option :timeout, type: :numeric, aliases: "-t", desc: "HTTP timeout seconds (default 120)"
    def ask(query = nil)
      agent = build_agent

      if options[:interactive]
        start_interactive(agent)
      elsif query
        agent.run(query)
      else
        puts "Error: provide a QUERY or use --interactive"
        exit 1
      end
    end

    private

    def build_agent
      Agent.new(
        model: options[:model],
        root: options[:root],
        confirm_patches: !options[:yes],
        http_timeout: options[:timeout]
      )
    end

    def start_interactive(agent)
      puts "Ollama Agent (type 'exit' to quit)"
      loop do
        print "> "
        input = $stdin.gets
        break if input.nil?

        line = input.chomp
        break if line == "exit"

        agent.run(line)
      end
    end
  end
end

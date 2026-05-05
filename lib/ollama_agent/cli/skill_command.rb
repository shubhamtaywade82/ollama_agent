# frozen_string_literal: true

require "thor"
require "json"

require_relative "../skills/registry"
require_relative "../skills/runner"

module OllamaAgent
  class CLI < Thor
    # Thor subcommand for running deterministic, JSON-contract skills.
    # Examples:
    #   ollama_agent skill list
    #   ollama_agent skill run architecture_refactor --code-file path/to/file.rb
    #   ollama_agent skill pipeline architecture_refactor performance_optimizer --code-file f.rb
    class SkillCommand < Thor
      desc "list", "List registered skills"
      def list
        names = Skills.registry.names
        return puts "No skills registered." if names.empty?

        names.each { |name| puts name }
      end

      desc "run NAME", "Run a single skill and print its JSON output"
      method_option :code_file, type: :string, desc: "Path to a file used as :code input"
      method_option :requirements, type: :string, desc: "Requirements brief for feature_builder"
      method_option :error, type: :string, desc: "Error message for debug_engineer"
      method_option :model, type: :string, desc: "Override skill model (OLLAMA_AGENT_SKILL_MODEL)"
      def run_skill(name)
        emit_json(Skills.registry.fetch(name).new(llm: build_llm).call(skill_input))
      end
      map "run" => :run_skill

      desc "pipeline NAME [NAME ...]", "Compose multiple skills into a deterministic pipeline"
      method_option :code_file, type: :string, desc: "Path to a file used as :code input"
      method_option :requirements, type: :string, desc: "Requirements brief"
      method_option :error, type: :string, desc: "Error message for debug_engineer"
      method_option :model, type: :string, desc: "Override skill model (OLLAMA_AGENT_SKILL_MODEL)"
      def pipeline(*names)
        raise Thor::Error, "specify at least one skill name" if names.empty?

        emit_json(Skills::Runner.new(names.map(&:to_sym), llm: build_llm).call(skill_input))
      end

      no_commands do
        def emit_json(payload)
          puts JSON.pretty_generate(payload)
        end

        def skill_input
          input = {}
          input[:code]         = read_code_file if options[:code_file]
          input[:requirements] = options[:requirements] if options[:requirements]
          input[:error]        = options[:error] if options[:error]
          input
        end

        def read_code_file
          File.read(File.expand_path(options[:code_file]), encoding: Encoding::UTF_8)
        rescue Errno::ENOENT
          raise Thor::Error, "code file not found: #{options[:code_file]}"
        end

        def build_llm
          Skills::LlmClient.new(model: options[:model])
        end
      end
    end
  end
end

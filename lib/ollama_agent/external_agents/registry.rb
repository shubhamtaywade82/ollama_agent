# frozen_string_literal: true

require "yaml"

module OllamaAgent
  module ExternalAgents
    # Loads merged default + user agent definitions (YAML).
    class Registry
      DEFAULT_FILE = File.join(__dir__, "default_agents.yml")
      USER_FILE = File.join(Dir.home, ".config", "ollama_agent", "agents.yml")

      attr_reader :agents

      def initialize(agents)
        @agents = agents
        @by_id = agents.to_h { |a| [a["id"].to_s, a] }
      end

      def self.load
        base = safe_read_yaml(DEFAULT_FILE)
        user_path = ENV.fetch("OLLAMA_AGENT_EXTERNAL_AGENTS_CONFIG", nil)
        user_path = USER_FILE if user_path.to_s.strip.empty? && File.file?(USER_FILE)
        user = user_path && File.file?(user_path.to_s) ? safe_read_yaml(user_path) : {}
        merged = merge_agents(base["agents"] || [], user["agents"] || [])
        new(merged)
      end

      def self.safe_read_yaml(path)
        YAML.safe_load(
          File.read(path, encoding: Encoding::UTF_8),
          permitted_classes: [],
          aliases: true
        ) || {}
      end

      def self.merge_agents(base, extra)
        by_id = base.to_h { |a| [a["id"].to_s, a] }
        extra.each do |a|
          id = a["id"].to_s
          by_id[id] = by_id[id] ? by_id[id].merge(a) : a
        end
        by_id.values
      end

      def find(id)
        @by_id[id.to_s]
      end
    end
  end
end

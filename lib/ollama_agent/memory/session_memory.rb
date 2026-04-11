# frozen_string_literal: true

require "yaml"
require "fileutils"

module OllamaAgent
  module Memory
    # Session-scoped key-value store for goals, task progress, and intermediate state.
    # Persisted to YAML under .ollama_agent/memory/<session_id>.yml.
    # Outlives a single run but is scoped to a session.
    class SessionMemory
      attr_reader :session_id

      def initialize(root:, session_id: nil)
        @root       = File.expand_path(root)
        @session_id = session_id || "default"
        @store      = load_or_initialize
      end

      # @param key   [String, Symbol]
      # @param value [Object]  must be YAML-serialisable
      def set(key, value)
        @store[key.to_s] = value
        persist!
        value
      end

      def get(key)
        @store[key.to_s]
      end

      def delete(key)
        @store.delete(key.to_s)
        persist!
      end

      def keys
        @store.keys
      end

      def all
        @store.dup
      end

      def clear!
        @store = {}
        persist!
      end

      # Active goals tracking
      def set_goal(description)
        goals = @store.fetch("_goals", [])
        goals << { description: description, status: "active", added_at: Time.now.iso8601 }
        set("_goals", goals)
      end

      def complete_goal(description)
        goals = @store.fetch("_goals", [])
        goals.each { |g| g[:status] = "done" if g[:description] == description }
        set("_goals", goals)
      end

      def active_goals
        @store.fetch("_goals", []).select { |g| g[:status] == "active" }
      end

      private

      def memory_dir
        File.join(@root, ".ollama_agent", "memory")
      end

      def memory_path
        File.join(memory_dir, "#{@session_id}.yml")
      end

      def load_or_initialize
        return {} unless File.exist?(memory_path)

        YAML.safe_load_file(memory_path, permitted_classes: [Symbol, Time]) || {}
      rescue StandardError
        {}
      end

      def persist!
        FileUtils.mkdir_p(memory_dir)
        File.write(memory_path, YAML.dump(@store))
      rescue StandardError
        nil
      end
    end
  end
end

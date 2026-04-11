# frozen_string_literal: true

require "yaml"
require "fileutils"
require "time"

module OllamaAgent
  module Memory
    # Persistent cross-session, cross-project memory.
    # Stores user preferences, project facts, and reusable summaries.
    # Backed by YAML files in ~/.config/ollama_agent/memory/<namespace>.yml
    class LongTerm
      DEFAULT_BASE = File.join(Dir.home, ".config", "ollama_agent", "memory")

      Entry = Data.define(:key, :value, :namespace, :created_at, :updated_at)

      def initialize(base_path: DEFAULT_BASE)
        @base_path = base_path
      end

      # Store a value under key in namespace.
      # @param key       [String]
      # @param value     [Object]   YAML-serialisable
      # @param namespace [String]
      def store(key, value, namespace: "default")
        data = load_namespace(namespace)
        now  = Time.now.iso8601

        data[key.to_s] = {
          "value"      => value,
          "created_at" => data.dig(key.to_s, "created_at") || now,
          "updated_at" => now
        }

        persist_namespace(namespace, data)
        value
      end

      # Fetch a value. Returns nil if missing.
      def fetch(key, namespace: "default")
        load_namespace(namespace).dig(key.to_s, "value")
      end

      # All entries in namespace as {key => value} hash.
      def all(namespace: "default")
        load_namespace(namespace).transform_values { |v| v["value"] }
      end

      # Delete a key.
      def delete(key, namespace: "default")
        data = load_namespace(namespace)
        removed = data.delete(key.to_s)
        persist_namespace(namespace, data) if removed
        removed
      end

      # List all keys in a namespace.
      def keys(namespace: "default")
        load_namespace(namespace).keys
      end

      # Search for entries whose key or value matches a pattern.
      def search(pattern, namespace: "default")
        data = load_namespace(namespace)
        re   = Regexp.new(pattern, Regexp::IGNORECASE) rescue nil
        return {} unless re

        data.select { |k, v| re.match?(k) || re.match?(v["value"].to_s) }
            .transform_values { |v| v["value"] }
      end

      # All namespace names that have been created.
      def namespaces
        return [] unless File.directory?(@base_path)

        Dir.glob(File.join(@base_path, "*.yml"))
           .map { |f| File.basename(f, ".yml") }
      end

      def clear_namespace!(namespace)
        path = namespace_path(namespace)
        File.delete(path) if File.exist?(path)
      end

      private

      def namespace_path(namespace)
        safe = namespace.to_s.gsub(/[^a-zA-Z0-9_-]/, "_")
        File.join(@base_path, "#{safe}.yml")
      end

      def load_namespace(namespace)
        path = namespace_path(namespace)
        return {} unless File.exist?(path)

        YAML.safe_load_file(path) || {}
      rescue StandardError
        {}
      end

      def persist_namespace(namespace, data)
        FileUtils.mkdir_p(@base_path)
        File.write(namespace_path(namespace), YAML.dump(data))
      rescue StandardError
        nil
      end
    end
  end
end

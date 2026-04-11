# frozen_string_literal: true

require_relative "registry"

module OllamaAgent
  module Plugins
    # Loads plugins from:
    #   1. OLLAMA_AGENT_PLUGINS env var (comma-separated require paths)
    #   2. ~/.config/ollama_agent/plugins.rb  (user global plugins)
    #   3. <project_root>/.ollama_agent/plugins.rb  (project-local plugins)
    #   4. Gem-installed plugins with name matching "ollama_agent_*"
    #
    # Each loaded file is expected to call:
    #   OllamaAgent::Plugins::Registry.register(:my_plugin) { |r| ... }
    class Loader
      GLOBAL_PLUGINS_PATH  = File.join(Dir.home, ".config", "ollama_agent", "plugins.rb")
      GEM_PLUGIN_PREFIX    = "ollama_agent_"

      def initialize(root: Dir.pwd, registry: nil)
        @root     = File.expand_path(root)
        @registry = registry || Registry.instance
      end

      # Load all applicable plugins.
      # @param skip_gems [Boolean] skip gem-installed plugins (useful in tests)
      # @return [Array<String>] paths/names of successfully loaded plugins
      def load_all(skip_gems: false)
        loaded = []

        loaded.concat(load_env_plugins)
        loaded.concat(load_file_plugin(GLOBAL_PLUGINS_PATH))
        loaded.concat(load_file_plugin(project_plugins_path))
        loaded.concat(load_gem_plugins) unless skip_gems

        loaded
      end

      # Load a single plugin from a require path or file.
      def load_plugin(path_or_require)
        if File.exist?(path_or_require)
          require File.expand_path(path_or_require)
        else
          require path_or_require
        end
        [path_or_require]
      rescue LoadError => e
        warn "ollama_agent: plugin load failed (#{path_or_require}): #{e.message}" if debug?
        []
      rescue StandardError => e
        warn "ollama_agent: plugin error (#{path_or_require}): #{e.message}"
        []
      end

      private

      def load_env_plugins
        env_val = ENV.fetch("OLLAMA_AGENT_PLUGINS", "").strip
        return [] if env_val.empty?

        env_val.split(",").flat_map { |p| load_plugin(p.strip) }
      end

      def load_file_plugin(path)
        return [] unless File.exist?(path)

        load_plugin(path)
      end

      def load_gem_plugins
        return [] unless defined?(Gem)

        loaded = []
        Gem::Specification.each do |spec|
          next unless spec.name.start_with?(GEM_PLUGIN_PREFIX)

          plugin_file = File.join(spec.gem_dir, "lib", "#{spec.name}.rb")
          next unless File.exist?(plugin_file)

          loaded.concat(load_plugin(plugin_file))
        end
        loaded
      rescue StandardError
        []
      end

      def project_plugins_path
        File.join(@root, ".ollama_agent", "plugins.rb")
      end

      def debug?
        ENV["OLLAMA_AGENT_DEBUG"] == "1"
      end
    end
  end
end

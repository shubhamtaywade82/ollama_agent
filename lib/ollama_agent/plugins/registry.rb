# frozen_string_literal: true

module OllamaAgent
  module Plugins
    # Central plugin registry.
    #
    # A plugin is any object (module, class, or struct) that can register
    # extensions at one or more extension points.
    #
    # Extension points:
    #   :tools            — Array<Tools::Base subclass instances>
    #   :prompts          — Array<Hash { name:, content: }>
    #   :policies         — Array<Proc(tool, args, ctx) → nil | String>
    #   :providers        — Array<Providers::Base instances>
    #   :postprocessors   — Array<Proc(response) → response>
    #   :memory_adapters  — Array<Memory::Base-like objects>
    #   :command_handlers — Array<Hash { slash_command:, handler: Proc }>
    #
    # @example Register a plugin inline
    #   OllamaAgent::Plugins::Registry.register(:my_plugin) do |r|
    #     r.extend(:tools, MyTool.new)
    #     r.extend(:prompts, name: "code_review", content: File.read("prompts/review.md"))
    #   end
    class Registry
      EXTENSION_POINTS = %i[
        tools prompts policies providers
        postprocessors memory_adapters command_handlers
      ].freeze

      class << self
        def instance
          @instance ||= new
        end

        # Delegate class methods to the singleton.
        def register(name, plugin = nil, &) = instance.register(name, plugin, &)
        def extensions_for(point)                = instance.extensions_for(point)
        def all_tools                            = instance.extensions_for(:tools)
        def all_prompts                          = instance.extensions_for(:prompts)
        def all_policies                         = instance.extensions_for(:policies)
        def all_providers                        = instance.extensions_for(:providers)
        def all_postprocessors                   = instance.extensions_for(:postprocessors)
        def all_command_handlers                 = instance.extensions_for(:command_handlers)
        def plugin_names                         = instance.plugin_names
        def reset!                               = instance.reset!
      end

      def initialize
        reset!
      end

      # Register a plugin by name.
      # @param name   [Symbol, String]   unique plugin identifier
      # @param plugin [Object, nil]      plugin object (must respond to #register(registry))
      # @param block  [Proc]             alternative: inline registration block
      def register(name, plugin = nil, &block)
        name = name.to_sym
        raise ArgumentError, "Plugin #{name} is already registered" if @plugins.key?(name)

        @plugins[name] = plugin

        if block
          block.call(self)
        elsif plugin.respond_to?(:register)
          plugin.register(self)
        end
      end

      # Add an extension at a specific extension point.
      # @param point   [Symbol]  one of EXTENSION_POINTS
      # @param handler [Object]  see per-point documentation above
      def extend(point, handler)
        point = point.to_sym
        unless EXTENSION_POINTS.include?(point)
          raise ArgumentError,
                "Unknown extension point: #{point}. Valid: #{EXTENSION_POINTS.join(", ")}"
        end

        @extensions[point] << handler
      end

      # Shorthand helpers
      def add_tool(tool)         = extend(:tools, tool)
      def add_prompt(hash)       = extend(:prompts, hash)
      def add_policy(&block)     = extend(:policies, block)
      def add_provider(provider) = extend(:providers, provider)

      def add_command(slash_command:,
                      &handler)
        extend(:command_handlers, { slash_command: slash_command, handler: handler })
      end

      def extensions_for(point)
        @extensions[point.to_sym].dup
      end

      def plugin_names
        @plugins.keys
      end

      def reset!
        @plugins    = {}
        @extensions = Hash.new { |h, k| h[k] = [] }
      end
    end
  end
end

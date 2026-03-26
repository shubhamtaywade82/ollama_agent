# frozen_string_literal: true

module OllamaAgent
  # Provides tool registration and execution helpers for OllamaAgent.
  module Tools
    # Delegate class-methods so consumers call OllamaAgent::Tools.register(...)
    def self.register(name, schema:, &)     = Registry.register(name, schema: schema, &)
    def self.custom_tool?(name)             = Registry.custom_tool?(name)

    def self.execute_custom(name, args, root:, read_only:)
      Registry.execute_custom(name, args, root: root, read_only: read_only)
    end

    def self.custom_schemas                 = Registry.custom_schemas
    def self.reset!                         = Registry.reset!

    # Stores and executes custom tool definitions registered by users.
    module Registry
      @custom_tools = {}

      class << self
        def register(name, schema:, &handler)
          raise ArgumentError, "handler block required" unless block_given?
          raise ArgumentError, "schema must be a Hash" unless schema.is_a?(Hash)

          @custom_tools[name.to_s] = { schema: schema, handler: handler }
        end

        def custom_tool?(name)
          @custom_tools.key?(name.to_s)
        end

        def execute_custom(name, args, root:, read_only:)
          entry = @custom_tools[name.to_s]
          return "Unknown custom tool: #{name}" unless entry

          entry[:handler].call(args, root: root, read_only: read_only)
        end

        def custom_schemas
          @custom_tools.map do |name, entry|
            {
              type: "function",
              function: entry[:schema].merge(name: name)
            }
          end
        end

        def reset!
          @custom_tools = {}
        end
      end
    end
  end
end

# lib/ollama_agent/tools/registry.rb
# frozen_string_literal: true

module OllamaAgent
  module Tools
    # Delegate class-methods so consumers call OllamaAgent::Tools.register(...)
    def self.register(name, schema:, &block)     = Registry.register(name, schema: schema, &block)
    def self.custom_tool?(name)                  = Registry.custom_tool?(name)
    def self.execute_custom(name, args, **kw)    = Registry.execute_custom(name, args, **kw)
    def self.custom_schemas                      = Registry.custom_schemas
    def self.reset!                              = Registry.reset!

    module Registry
      @custom_tools = {}

      class << self
        def register(name, schema:, &handler)
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

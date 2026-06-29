# frozen_string_literal: true

module OllamaAgent
  module Tools
    class EnhancedRegistry
      class << self
        def register(tool_class)
          @tools ||= {}
          instance = tool_class.new
          @tools[instance.name] = instance
        end

        def all_instances
          @tools ||= {}
          @tools.values
        end

        def schemas(read_only: false)
          instances = all_instances
          instances = instances.select(&:read_only_safe) if read_only
          instances.map(&:to_ollama_schema)
        end

        def execute(name, args, context: {})
          instance = all_instances.find { |t| t.name == name }
          return nil unless instance

          check_approval!(instance, context)
          instance.call(args, context: context)
        end

        private

        def check_approval!(tool, context)
          return unless tool.requires_approval

          unless context[:approval_gate]
            raise OllamaAgent::Error, "#{tool.name} requires approval but no approval_gate in context"
          end

          context[:approval_gate].call(tool.name, tool.description)
        end
      end
    end
  end
end

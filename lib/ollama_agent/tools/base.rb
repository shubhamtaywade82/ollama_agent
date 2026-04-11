# frozen_string_literal: true

module OllamaAgent
  module Tools
    # Base class for all typed, permissioned, auditable tools.
    #
    # Subclasses must implement #call(args, context:) and define:
    #   - name         String
    #   - description  String
    #   - input_schema Hash   (JSON schema for arguments)
    #
    # @example
    #   class MyTool < OllamaAgent::Tools::Base
    #     tool_name        "my_tool"
    #     tool_description "Does something useful"
    #     tool_risk        :low
    #     tool_schema      { type: "object", properties: { ... }, required: [...] }
    #
    #     def call(args, context:)
    #       { result: args["input"].upcase }
    #     end
    #   end
    class Base
      RISK_LEVELS = %i[low medium high critical].freeze

      class << self
        def tool_name(name = nil)
          @tool_name = name.to_s if name
          @tool_name || raise(NotImplementedError, "#{self}.tool_name not set")
        end

        def tool_description(desc = nil)
          @tool_description = desc if desc
          @tool_description || ""
        end

        def tool_risk(level = nil)
          @tool_risk = level.to_sym if level
          @tool_risk || :low
        end

        def tool_requires_approval(flag = nil)
          @tool_requires_approval = flag unless flag.nil?
          @tool_requires_approval.nil? ? (@tool_risk || :low) == :high || (@tool_risk || :low) == :critical : @tool_requires_approval
        end

        def tool_schema(schema = nil)
          @tool_schema = schema if schema
          @tool_schema || { type: "object", properties: {}, required: [] }
        end

        def tool_output_schema(schema = nil)
          @tool_output_schema = schema if schema
          @tool_output_schema
        end

        def inherited(subclass)
          super
          # subclass inherits nil overrides so defaults still apply
        end
      end

      attr_reader :name, :description, :input_schema, :output_schema, :risk_level, :requires_approval

      def initialize
        @name               = self.class.tool_name
        @description        = self.class.tool_description
        @input_schema       = self.class.tool_schema
        @output_schema      = self.class.tool_output_schema
        @risk_level         = self.class.tool_risk
        @requires_approval  = self.class.tool_requires_approval
      end

      # Execute the tool.
      # @param args    [Hash]   validated argument hash
      # @param context [Hash]   runtime context: { root:, read_only:, run_id:, … }
      # @return [String, Hash]  result surfaced back to the model
      def call(args, context: {})
        raise NotImplementedError, "#{self.class}#call not implemented"
      end

      # JSON schema formatted for Ollama / OpenAI tool_call
      def to_ollama_schema
        {
          type: "function",
          function: {
            name:        @name,
            description: @description,
            parameters:  @input_schema
          }
        }
      end

      # Anthropic-format tool definition
      def to_anthropic_schema
        {
          name:         @name,
          description:  @description,
          input_schema: @input_schema
        }
      end

      def to_s
        "#<Tool:#{@name} risk=#{@risk_level} approval=#{@requires_approval}>"
      end
    end
  end
end

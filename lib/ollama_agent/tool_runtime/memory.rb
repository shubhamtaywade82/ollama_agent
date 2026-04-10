# frozen_string_literal: true

module OllamaAgent
  module ToolRuntime
    # Short-term transcript of planner output, resolved actions, and tool results.
    class Memory
      # @return [String, nil] optional text injected into planner prompts (e.g. registry descriptions)
      attr_accessor :tool_descriptions

      def initialize(limit: 10)
        @steps = []
        @limit = [Integer(limit), 1].max
        @tool_descriptions = nil
      end

      def append(thought:, action:, result:)
        @steps << { thought: thought, action: action, result: result }
        @steps.shift while @steps.size > @limit
      end

      def recent(last_n = nil)
        return @steps.dup if last_n.nil?

        @steps.last(Integer(last_n))
      end

      def tool_descriptions_for_prompt
        @tool_descriptions.to_s
      end
    end
  end
end

# frozen_string_literal: true

require "json"

module OllamaAgent
  module ToolRuntime
    # Per-run tool lookup and prompt text for available tools.
    class Registry
      def initialize(tools = [])
        @tools = {}
        Array(tools).each { |tool| register(tool) }
      end

      def register(tool)
        raise ArgumentError, "tool must respond to #name" unless tool.respond_to?(:name)

        key = tool.name.to_s
        raise ArgumentError, "duplicate tool name: #{key}" if @tools.key?(key)

        @tools[key] = tool
      end

      # @param plan [Hash] must include "tool" (or :tool); optional "args" / :args
      # @return [Hash, nil] `{ tool: Tool instance, args: Hash }` or nil if unknown
      def resolve(plan)
        return nil unless plan.is_a?(Hash)

        tool_name = tool_name_from(plan)
        return nil if tool_name.nil? || tool_name.to_s.strip.empty?

        tool = @tools[tool_name.to_s]
        return nil unless tool

        { tool: tool, args: normalize_args(plan) }
      end

      def descriptions_for_prompt
        @tools.values.map do |t|
          "#{t.name}: #{t.description} schema=#{JSON.generate(t.schema)}"
        end.join("\n")
      end

      private

      def tool_name_from(plan)
        plan["tool"] || plan[:tool]
      end

      def normalize_args(plan)
        args = plan["args"] || plan[:args] || {}
        args = {} unless args.is_a?(Hash)
        stringify_keys(args)
      end

      def stringify_keys(hash)
        hash.transform_keys(&:to_s)
      end
    end
  end
end

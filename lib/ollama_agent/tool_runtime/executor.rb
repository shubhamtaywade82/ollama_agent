# frozen_string_literal: true

module OllamaAgent
  module ToolRuntime
    # Runs {Tool#call} behind an optional validator; normalizes errors to a result Hash.
    class Executor
      def initialize(validator: nil)
        @validator = validator
      end

      # @param action [Hash] `{ tool: Tool, args: Hash }`
      # @return [Object] tool return value, or `{ "status" => "error", "error" => String }` on failure
      def execute(action)
        tool = action[:tool]
        args = action[:args].is_a?(Hash) ? action[:args] : {}

        args = @validator.validate(tool.name, args) if validate_with?(tool, args)

        tool.call(args)
      rescue StandardError => e
        { "status" => "error", "error" => e.message }
      end

      private

      def validate_with?(tool, _args)
        return false if @validator.nil?
        return false unless @validator.respond_to?(:validate)

        tool.respond_to?(:name)
      end
    end
  end
end

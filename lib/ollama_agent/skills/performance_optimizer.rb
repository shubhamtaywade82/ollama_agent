# frozen_string_literal: true

require_relative "base"

module OllamaAgent
  module Skills
    # Identifies bottlenecks and returns an optimized version of the code.
    class PerformanceOptimizer < Base
      register_as :performance_optimizer

      SCHEMA = {
        type: "object",
        required: %w[bottlenecks optimizations optimized_code],
        properties: {
          bottlenecks: { type: "array" },
          optimizations: { type: "array" },
          optimized_code: { type: "string", minLength: 1 }
        }
      }.freeze

      protected

      def validated_input!(input)
        super
        raise ArgumentError, "missing :code" if input[:code].to_s.strip.empty?
      end

      def prompt(input)
        <<~PROMPT
          You are a senior performance engineer.

          Optimize the code for speed, memory usage, and scalability.
          Behavior must remain identical.

          Respond with ONLY a JSON object matching this contract:
          {
            "bottlenecks": ["..."],
            "optimizations": ["..."],
            "optimized_code": "string"
          }

          CODE:
          #{input[:code]}
        PROMPT
      end
    end
  end
end

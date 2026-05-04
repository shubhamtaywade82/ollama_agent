# frozen_string_literal: true

require_relative "base"

module OllamaAgent
  module Skills
    # Investigates a bug from a code excerpt and (optionally) an error message.
    class DebugEngineer < Base
      register_as :debug_engineer

      SCHEMA = {
        type: "object",
        required: %w[root_cause repair_plan fixed_code],
        properties: {
          root_cause: { type: "string", minLength: 1 },
          repair_plan: { type: "array" },
          edge_cases: { type: "array" },
          fixed_code: { type: "string", minLength: 1 }
        }
      }.freeze

      protected

      def validated_input!(input)
        super
        raise ArgumentError, "missing :code" if input[:code].to_s.strip.empty?
      end

      def prompt(input)
        <<~PROMPT
          You are a senior debugging engineer triaging a production issue.

          Analyze the code, find the root cause, and propose a robust fix.
          Consider edge cases and performance.

          Respond with ONLY a JSON object matching this contract:
          {
            "root_cause": "string",
            "repair_plan": ["step 1", "step 2"],
            "edge_cases": ["..."],
            "fixed_code": "string"
          }

          ERROR:
          #{input[:error] || "(none provided)"}

          CODE:
          #{input[:code]}
        PROMPT
      end
    end
  end
end

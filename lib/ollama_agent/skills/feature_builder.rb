# frozen_string_literal: true

require_relative "base"

module OllamaAgent
  module Skills
    # Designs and implements a production-ready feature from a requirements brief.
    class FeatureBuilder < Base
      register_as :feature_builder

      SCHEMA = {
        type: "object",
        required: %w[architecture_summary folder_structure data_flow implementation
                     edge_cases error_handling],
        properties: {
          architecture_summary: { type: "string", minLength: 1 },
          folder_structure: { type: "array" },
          data_flow: { type: "string", minLength: 1 },
          implementation: { type: "string", minLength: 1 },
          edge_cases: { type: "array" },
          error_handling: { type: "array" },
          performance_notes: { type: "string" }
        }
      }.freeze

      protected

      def validated_input!(input)
        super
        raise ArgumentError, "missing :requirements" if input[:requirements].to_s.strip.empty?
      end

      def prompt(input)
        <<~PROMPT
          You are a senior software engineer building a production-ready feature.

          Design the architecture, then provide a complete, scalable implementation.

          Respond with ONLY a JSON object matching this contract:
          {
            "architecture_summary": "string",
            "folder_structure": ["path/to/file.rb"],
            "data_flow": "string",
            "implementation": "string",
            "edge_cases": ["..."],
            "error_handling": ["..."],
            "performance_notes": "string"
          }

          REQUIREMENTS:
          #{input[:requirements]}

          CONSTRAINTS:
          #{input[:constraints] || "(none)"}
        PROMPT
      end
    end
  end
end

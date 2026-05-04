# frozen_string_literal: true

require_relative "base"

module OllamaAgent
  module Skills
    # Refactors a code blob into a clean architecture without changing behavior.
    class ArchitectureRefactorer < Base
      register_as :architecture_refactor

      SCHEMA = {
        type: "object",
        required: %w[folder_structure architecture_notes refactored_code],
        properties: {
          folder_structure: { type: "array" },
          architecture_notes: { type: "string", minLength: 1 },
          refactored_code: { type: "string", minLength: 1 }
        }
      }.freeze

      protected

      def validated_input!(input)
        super
        raise ArgumentError, "missing :code" if input[:code].to_s.strip.empty?
      end

      def prompt(input)
        <<~PROMPT
          You are a staff-level engineer.

          Refactor the code into clean architecture.

          RULES:
          - Do not change behavior
          - Reduce coupling
          - Increase modularity

          Respond with ONLY a JSON object matching this contract:
          {
            "folder_structure": ["path/one.rb", "path/two.rb"],
            "architecture_notes": "string",
            "refactored_code": "string"
          }

          CODE:
          #{input[:code]}
        PROMPT
      end
    end
  end
end

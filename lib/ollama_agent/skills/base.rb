# frozen_string_literal: true

require_relative "../core/schema_validator"
require_relative "json_extractor"
require_relative "llm_client"

module OllamaAgent
  module Skills
    # Template Method base for deterministic, JSON-contract skills.
    # Subclasses implement +#prompt(input)+ and define a +SCHEMA+ constant.
    # The base class drives the pipeline:
    #   prompt → llm.generate → JsonExtractor.parse → SchemaValidator.validate!
    class Base
      class ContractError < OllamaAgent::Error; end

      def self.skill_id
        @skill_id || raise(NotImplementedError, "#{name} must declare skill_id via `register_as`")
      end

      # Self-register the skill in the shared registry.
      def self.register_as(id)
        @skill_id = id.to_sym
        Skills.registry.register(@skill_id, self)
      end

      def initialize(llm: nil)
        @llm = llm || LlmClient.new
      end

      def call(input)
        validated_input!(input)
        raw    = @llm.generate(prompt(input))
        parsed = JsonExtractor.parse(raw)
        validate_contract!(parsed)
        parsed
      end

      protected

      # Override to enforce input shape; default accepts any Hash.
      def validated_input!(input)
        raise ArgumentError, "skill input must be a Hash, got #{input.class}" unless input.is_a?(Hash)
      end

      def prompt(_input)
        raise NotImplementedError, "#{self.class}#prompt must be implemented"
      end

      def validate_contract!(parsed)
        schema = self.class.const_get(:SCHEMA)
        Core::SchemaValidator.new.validate!(schema, parsed)
      rescue Core::SchemaValidator::ValidationError => e
        raise ContractError, "#{self.class.skill_id} contract violation: #{e.message}"
      end
    end
  end
end

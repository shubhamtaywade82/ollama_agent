# frozen_string_literal: true

require_relative "registry"

module OllamaAgent
  module Skills
    # Composes a deterministic pipeline of skills. Each skill receives the
    # output of the previous one merged into the original input, so downstream
    # skills can chain on prior results without losing context.
    class Runner
      def initialize(steps, llm: nil)
        raise ArgumentError, "pipeline must contain at least one skill" if steps.empty?

        @skills = steps.map { |s| build_skill(s, llm: llm) }
      end

      def call(input)
        @skills.reduce(input) { |acc, skill| acc.merge(skill.call(acc)) }
      end

      private

      def build_skill(step, llm:)
        klass = resolve(step)
        klass.new(llm: llm)
      end

      def resolve(step)
        return Skills.registry.fetch(step) if step.is_a?(Symbol) || step.is_a?(String)

        step
      end
    end
  end
end

# frozen_string_literal: true

module OllamaAgent
  # Deterministic skill system: JSON-contract pipelines for production tasks
  # (refactor, optimize, debug, build) running against any registered provider.
  module Skills
    # Registry of named skill classes. Skills self-register at load time so the
    # CLI can resolve them by id (e.g. :architecture_refactor).
    class Registry
      class UnknownSkill < OllamaAgent::Error; end

      def initialize
        @skills = {}
      end

      def register(name, klass)
        @skills[name.to_sym] = klass
      end

      def fetch(name)
        @skills.fetch(name.to_sym) do
          raise UnknownSkill, "unknown skill: #{name.inspect}. Known: #{names.join(", ")}"
        end
      end

      def names
        @skills.keys.sort
      end

      def each(&)
        @skills.each(&)
      end
    end

    def self.registry
      @registry ||= Registry.new
    end
  end
end

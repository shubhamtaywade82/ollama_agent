# frozen_string_literal: true

module OllamaAgent
  module RuntimeCommandSystem
    # Central source of command metadata and command-aware completer bindings.
    class CommandRegistry
      CommandSpec = Struct.new(:name, :description, :completer, :validator, :executor, keyword_init: true) do
        def slash_name
          name.to_s.start_with?("/") ? name.to_s : "/#{name}"
        end
      end

      def initialize
        @commands = {}
      end

      def register(name:, description:, completer: nil, validator: nil, executor: nil)
        normalized = normalize_name(name)
        @commands[normalized] = CommandSpec.new(
          name: normalized,
          description: description.to_s,
          completer: completer,
          validator: validator,
          executor: executor
        )
      end

      def find(name)
        @commands[normalize_name(name)]
      end

      def matching_prefix(prefix)
        normalized = normalize_name(prefix)
        @commands.values.select { |spec| spec.name.start_with?(normalized) }
      end

      def all
        @commands.values
      end

      private

      def normalize_name(name)
        name.to_s.delete_prefix("/").downcase
      end
    end
  end
end

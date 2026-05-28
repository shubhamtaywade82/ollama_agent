# frozen_string_literal: true

require_relative "ast"
require_relative "suggestion"

module OllamaAgent
  module RuntimeCommandSystem
    # Routes slash-command input to command, model, provider, or plugin completers.
    class SuggestionEngine
      def initialize(registry:)
        @registry = registry
      end

      def complete(input:, cursor_pos: nil, session: {})
        text = input.to_s
        return [] unless text.start_with?("/")

        ast = AST::Parser.parse(text, cursor_pos || text.length)
        return [] unless ast

        command = @registry.find(ast.name)
        return command_completions(ast.name) unless command && ast.argument_context?

        command.completer&.suggestions(ast: ast, cursor_pos: cursor_pos || text.length, session: session) || []
      end

      private

      def command_completions(prefix)
        @registry.matching_prefix(prefix).map do |command|
          Suggestion.new(
            text: command.slash_name,
            type: :command,
            description: command.description,
            replacement_start: 0
          )
        end
      end
    end
  end
end

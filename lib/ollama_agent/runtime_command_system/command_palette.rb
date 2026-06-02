# frozen_string_literal: true

require_relative "command_registry"
require_relative "completers"
require_relative "suggestion_engine"
require_relative "ghost_text"
require_relative "interactive_menu"

module OllamaAgent
  module RuntimeCommandSystem
    # Facade for the AI Runtime Shell command palette.
    class CommandPalette
      attr_reader :registry, :suggestion_engine, :ghost_renderer, :menu

      def initialize(commands:, session: {})
        @session = session
        @registry = CommandRegistry.new
        @suggestion_engine = SuggestionEngine.new(registry: @registry)
        @ghost_renderer = GhostTextRenderer.new(@suggestion_engine)
        @menu = InteractiveMenu.new
        register_commands(commands)
      end

      def suggestions(input, cursor_pos = nil)
        @suggestion_engine.complete(input: input, cursor_pos: cursor_pos || input.to_s.length, session: @session)
      end

      def ghost_text(input, cursor_pos = nil)
        @ghost_renderer.ghost_text(input: input, cursor_pos: cursor_pos || input.to_s.length, session: @session)
      end

      def accept_ghost(input, cursor_pos = nil)
        ghost_text(input, cursor_pos)&.full_completion
      end

      private

      def register_commands(commands)
        commands.each do |name, description|
          @registry.register(name: name, description: description, completer: completer_for(name))
        end
      end

      def completer_for(name)
        case name.to_s.delete_prefix("/")
        when "model" then Completers::ModelCompleter.new
        when "models" then Completers::ModelCompleter.new
        when "provider" then Completers::ProviderCompleter.new
        end
      end
    end
  end
end

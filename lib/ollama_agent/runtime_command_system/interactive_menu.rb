# frozen_string_literal: true

module OllamaAgent
  module RuntimeCommandSystem
    # State holder for dropdown selection. Rendering is owned by the TUI layer.
    class InteractiveMenu
      attr_reader :suggestions, :index

      def initialize
        @visible = false
        @suggestions = []
        @index = 0
      end

      def show(suggestions)
        @suggestions = Array(suggestions)
        @index = 0
        @visible = @suggestions.any?
      end

      def hide
        @visible = false
      end

      def visible?
        @visible
      end

      def next
        return nil if @suggestions.empty?

        @index = (@index + 1) % @suggestions.length
        selected
      end

      def previous
        return nil if @suggestions.empty?

        @index = (@index - 1) % @suggestions.length
        selected
      end

      def selected
        @suggestions[@index]
      end
    end
  end
end

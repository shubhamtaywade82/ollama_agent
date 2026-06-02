# frozen_string_literal: true

module OllamaAgent
  module RuntimeCommandSystem
    GhostText = Struct.new(:suffix, :full_completion, :suggestion, keyword_init: true)

    # Computes visual-only inline completions without mutating the edit buffer.
    class GhostTextRenderer
      def initialize(suggestion_engine)
        @suggestion_engine = suggestion_engine
      end

      def ghost_text(input:, cursor_pos: nil, session: {})
        text = input.to_s
        suggestions = @suggestion_engine.complete(input: text, cursor_pos: cursor_pos || text.length, session: session)
        suggestion = suggestions.first
        return nil unless suggestion

        start = suggestion.replacement_start
        typed = text[start..] || ""
        return nil unless suggestion.text.start_with?(typed)

        suffix = suggestion.text[typed.length..]
        return nil if suffix.nil? || suffix.empty?

        GhostText.new(
          suffix: suffix,
          full_completion: "#{text[0...start]}#{suggestion.text}",
          suggestion: suggestion
        )
      end
    end
  end
end

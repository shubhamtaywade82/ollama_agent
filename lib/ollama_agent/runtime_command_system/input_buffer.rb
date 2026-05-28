# frozen_string_literal: true

module OllamaAgent
  module RuntimeCommandSystem
    module Input
      # Minimal mutable edit buffer independent from chat/provider runtimes.
      class Buffer
        attr_reader :text, :cursor_pos

        def initialize(text = "")
          @text = text.to_s.dup
          @cursor_pos = @text.length
        end

        def insert(chars)
          value = chars.to_s
          @text = @text[0...@cursor_pos] + value + @text[@cursor_pos..].to_s
          @cursor_pos += value.length
        end

        def backspace
          return if @cursor_pos.zero?

          @text = @text[0...(@cursor_pos - 1)] + @text[@cursor_pos..].to_s
          @cursor_pos -= 1
        end

        def move_cursor(delta)
          @cursor_pos = [[@cursor_pos + delta.to_i, 0].max, @text.length].min
        end

        def accept_ghost_text(ghost)
          @text = ghost.full_completion.to_s.dup
          @cursor_pos = @text.length
        end

        def command_mode?
          @text.start_with?("/")
        end
      end
    end
  end
end

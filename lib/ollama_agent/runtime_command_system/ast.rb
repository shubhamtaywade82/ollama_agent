# frozen_string_literal: true

module OllamaAgent
  module RuntimeCommandSystem
    module AST
      class CommandNode
        attr_reader :name, :arguments, :options, :raw, :cursor_pos

        def initialize(name:, arguments: [], options: {}, raw: "", cursor_pos: 0)
          @name = name.to_s
          @arguments = arguments
          @options = options
          @raw = raw.to_s
          @cursor_pos = cursor_pos.to_i
        end

        def command_text
          "/#{name}"
        end

        def current_argument
          arguments.last
        end

        def argument_context?
          raw.include?(" ")
        end
      end

      class ArgumentNode
        attr_reader :value, :position, :type

        def initialize(value:, position:, type: :string)
          @value = value.to_s
          @position = position.to_i
          @type = type.to_sym
        end

        def incomplete?
          value.empty?
        end
      end

      class Parser
        COMMAND_PATTERN = %r{\A/([a-zA-Z][a-zA-Z0-9_-]*)(.*)\z}
        TOKEN_PATTERN = /[^\s"]+|"[^"]*"/

        class << self
          def parse(input, cursor_pos = nil)
            text = input.to_s
            return nil unless text.start_with?("/")

            cursor = cursor_pos || text.length
            match = text.match(COMMAND_PATTERN)
            return partial_command(text, cursor) unless match

            name = match[1]
            tail = match[2].to_s
            CommandNode.new(
              name: name,
              arguments: parse_arguments(tail, name.length + 1),
              raw: text,
              cursor_pos: cursor
            )
          end

          private

          def partial_command(text, cursor)
            CommandNode.new(name: text.delete_prefix("/"), raw: text, cursor_pos: cursor)
          end

          def parse_arguments(tail, offset)
            return [] if tail.empty?

            args = []
            tail.scan(TOKEN_PATTERN) do |token|
              start = Regexp.last_match.begin(0) + offset
              value = token.delete_prefix('"').delete_suffix('"')
              args << ArgumentNode.new(value: value, position: start, type: infer_type(value))
            end
            args << ArgumentNode.new(value: "", position: offset + tail.length) if tail.end_with?(" ")
            args
          end

          def infer_type(token)
            return :model if token.include?(":")
            return :file if token.match?(/\.(?:png|jpe?g|gif|webp|pdf|txt|md)\z/i)

            :string
          end
        end
      end
    end
  end
end

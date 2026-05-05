# frozen_string_literal: true

require "json"

module OllamaAgent
  module Skills
    # Extracts the first balanced JSON object/array from raw LLM text.
    # Tolerates leading prose, trailing commentary, and ```json fenced blocks.
    # Skips brackets inside JSON string literals so embedded braces don't break parsing.
    module JsonExtractor
      class ExtractionError < OllamaAgent::Error; end

      FENCED = /```(?:json)?\s*(\{.*?\}|\[.*?\])\s*```/m
      CLOSERS = { "{" => "}", "[" => "]" }.freeze

      module_function

      def parse(text)
        JSON.parse(extract(text), symbolize_names: true)
      rescue JSON::ParserError => e
        raise ExtractionError, "invalid JSON in model output: #{e.message}"
      end

      def extract(text)
        raise ExtractionError, "empty model output" if text.to_s.strip.empty?

        fenced = text.match(FENCED)
        return fenced[1] if fenced

        balanced_slice(text) || raise(ExtractionError, "no JSON object found in model output")
      end

      def balanced_slice(text)
        start = text.index(/[{\[]/)
        return nil if start.nil?

        length = BalancedScan.new(text[start..]).length
        length && text[start, length]
      end

      # Walks the buffer once tracking bracket depth while ignoring brackets
      # nested inside JSON string literals. Returns the slice length that
      # closes the initial opener, or nil when the input is unbalanced.
      class BalancedScan
        def initialize(buffer)
          @buffer = buffer
          @opener = buffer[0]
          @closer = CLOSERS.fetch(@opener)
          @depth = 0
          @in_string = false
          @escape = false
        end

        def length
          @buffer.each_char.with_index do |char, idx|
            consume(char)
            return idx + 1 if !@in_string && @depth.zero? && idx.positive?
          end
          nil
        end

        private

        def consume(char)
          return advance_string(char) if @in_string

          @in_string = true if char == '"'
          @depth += 1 if char == @opener
          @depth -= 1 if char == @closer
        end

        def advance_string(char)
          if @escape then @escape = false
          elsif char == "\\" then @escape = true
          elsif char == '"' then @in_string = false
          end
        end
      end
    end
  end
end

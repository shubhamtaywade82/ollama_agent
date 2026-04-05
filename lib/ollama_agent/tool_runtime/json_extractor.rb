# frozen_string_literal: true

require "json"

module OllamaAgent
  module ToolRuntime
    # Pulls the first top-level JSON object from text using brace matching (strings respected).
    module JsonExtractor
      class << self
        def extract_object(text)
          raise ArgumentError, "text must be a String" unless text.is_a?(String)

          start_idx = text.index("{")
          raise JsonParseError, "no JSON object found" if start_idx.nil?

          slice = extract_balanced_object(text, start_idx)
          JSON.parse(slice)
        rescue JSON::ParserError => e
          raise JsonParseError, "invalid JSON: #{e.message}"
        end

        private

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength -- brace scanner with string/escape states
        def extract_balanced_object(str, start_idx)
          depth = 0
          i = start_idx
          in_string = false
          escape = false

          while i < str.length
            c = str[i]
            if escape
              escape = false
            elsif in_string
              case c
              when "\\"
                escape = true
              when '"'
                in_string = false
              end
            else
              case c
              when '"'
                in_string = true
              when "{"
                depth += 1
              when "}"
                depth -= 1
                return str[start_idx..i] if depth.zero?
              end
            end
            i += 1
          end

          raise JsonParseError, "unbalanced braces in JSON object"
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
      end
    end
  end
end

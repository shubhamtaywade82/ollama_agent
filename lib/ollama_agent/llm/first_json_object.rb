# frozen_string_literal: true

module OllamaAgent
  module LLM
    # Finds the first top-level balanced `{ ... }` slice, respecting string escapes.
    module FirstJsonObject
      module_function

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- brace depth + string escape scanner
      def extract(text)
        start_idx = text.index("{")
        return nil unless start_idx

        depth = 0
        in_string = false
        escape = false
        (start_idx...text.length).each do |i|
          c = text[i]
          if in_string
            if escape
              escape = false
            elsif c == "\\"
              escape = true
            elsif c == '"'
              in_string = false
            end
          elsif c == '"'
            in_string = true
          elsif c == "{"
            depth += 1
          elsif c == "}"
            depth -= 1
            return text[start_idx..i] if depth.zero?
          end
        end
        nil
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    end
  end
end

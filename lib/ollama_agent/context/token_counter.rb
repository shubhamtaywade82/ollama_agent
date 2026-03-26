# frozen_string_literal: true

module OllamaAgent
  module Context
    # Estimates token count using chars/4 integer division (floor).
    module TokenCounter
      module_function

      def estimate(text)
        text.to_s.length / 4
      end
    end
  end
end

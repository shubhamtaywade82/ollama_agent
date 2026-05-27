# frozen_string_literal: true

module OllamaAgent
  module LLM
    # Removes reasoning-only think blocks before downstream JSON parsing.
    module ThinkBlockStripper
      THINK_BLOCK = %r{<think>.*?</think>}m

      module_function

      def strip(text)
        text.to_s.gsub(THINK_BLOCK, "").strip
      end
    end
  end
end

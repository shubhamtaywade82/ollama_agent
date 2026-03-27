# frozen_string_literal: true

module OllamaAgent
  module Context
    # Estimates token count using chars/4 integer division (floor).
    # Auto-upgrades to tiktoken_ruby (gpt-4 tokenizer) if available in host bundle.
    module TokenCounter
      @tokenizer = nil
      @tiktoken_loaded = false

      def self.estimate(text)
        ensure_tiktoken_loaded
        return @tokenizer.encode(text.to_s).length if @tokenizer

        text.to_s.length / 4
      end

      def self.ensure_tiktoken_loaded
        return if @tiktoken_loaded

        begin
          require "tiktoken_ruby"
          @tokenizer = Tiktoken.encoding_for_model("gpt-4")
        rescue LoadError
          @tokenizer = nil
        ensure
          @tiktoken_loaded = true
        end
      end
      private_class_method :ensure_tiktoken_loaded
    end
  end
end

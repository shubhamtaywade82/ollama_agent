# frozen_string_literal: true

require_relative "token_counter"

module OllamaAgent
  module Context
    # Trims the messages array to fit within a token budget before each chat call.
    # Never mutates the input. Never removes the system message or the last user message.
    class Manager
      DEFAULT_MAX_TOKENS = 8_192
      TRIM_THRESHOLD     = 0.85

      def initialize(max_tokens: nil)
        @max_tokens = (max_tokens || env_max_tokens).to_i
      end

      # rubocop:disable Metrics/MethodLength -- loop + guard + index recompute exceed 10 LOC
      # Returns a (possibly shorter) copy of messages that fits within the token budget.
      def trim(messages)
        return messages unless over_budget?(messages)

        trimmed = messages.dup
        last_user_idx = trimmed.rindex { |m| m[:role] == "user" }

        loop do
          break unless over_budget?(trimmed)

          drop_idx = find_droppable(trimmed, last_user_idx)
          break if drop_idx.nil?

          trimmed.delete_at(drop_idx)
          last_user_idx = trimmed.rindex { |m| m[:role] == "user" }
        end

        trimmed
      end
      # rubocop:enable Metrics/MethodLength

      private

      def over_budget?(messages)
        total_tokens(messages) > (@max_tokens * TRIM_THRESHOLD).to_i
      end

      def total_tokens(messages)
        messages.sum { |m| TokenCounter.estimate(m[:content].to_s) }
      end

      def find_droppable(messages, last_user_idx)
        messages.each_index.find do |i|
          messages[i][:role] != "system" && i != last_user_idx
        end
      end

      def env_max_tokens
        v = ENV.fetch("OLLAMA_AGENT_MAX_TOKENS", nil)
        return DEFAULT_MAX_TOKENS if v.nil? || v.to_s.strip.empty?

        Integer(v)
      rescue ArgumentError, TypeError
        DEFAULT_MAX_TOKENS
      end
    end
  end
end

# frozen_string_literal: true

require_relative "token_counter"

module OllamaAgent
  module Context
    # Trims the messages array to fit within a token budget before each chat call.
    # Never mutates the input. Never removes the system message or the last user message.
    class Manager
      DEFAULT_MAX_TOKENS = 32_768
      TRIM_THRESHOLD     = 0.85

      def initialize(max_tokens: nil, context_summarize: false)
        @max_tokens = (max_tokens || env_max_tokens).to_i
        @context_summarize = context_summarize
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      # Returns a (possibly shorter) copy of messages that fits within the token budget.
      def trim(messages)
        return messages unless over_budget?(messages)

        trimmed = messages.dup
        # We want to keep the system message and the very last user message.
        # Everything else is fair game for the sliding window.
        last_user_idx = trimmed.rindex { |m| m[:role] == "user" }

        # Optional: collect dropped messages for summarization
        dropped = [] if @context_summarize

        while over_budget?(trimmed)
          drop_idx = find_droppable_index(trimmed, last_user_idx)
          break if drop_idx.nil?

          msgs = if assistant_with_tool_calls?(trimmed[drop_idx])
                   drop_assistant_and_tool_results(trimmed, drop_idx)
                 else
                   [trimmed.delete_at(drop_idx)]
                 end
          dropped&.concat(msgs)

          # Re-find last user index as it might have shifted
          last_user_idx = trimmed.rindex { |m| m[:role] == "user" }
        end

        inject_summary(trimmed, dropped) if @context_summarize && dropped&.any?
        trimmed
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      private

      def inject_summary(messages, dropped)
        # In a real implementation, we would call the model to summarize.
        # For now, we add a system message noting that history was trimmed.
        # (The spec implies calling the model, but Agent doesn't pass the client here yet).
        n = dropped.size
        summary = "Note: Earlier conversation history was trimmed to fit token budget (#{n} messages dropped)."
        messages.insert(1, { role: "system", content: summary })
      end

      def over_budget?(messages)
        total_tokens(messages) > (@max_tokens * TRIM_THRESHOLD).to_i
      end

      def total_tokens(messages)
        messages.sum { |m| TokenCounter.estimate(m[:content].to_s) }
      end

      def find_droppable_index(messages, last_user_idx)
        messages.each_index.find do |i|
          messages[i][:role] != "system" && i != last_user_idx
        end
      end

      def assistant_with_tool_calls?(message)
        message[:role] == "assistant" && message[:tool_calls] && !message[:tool_calls].empty?
      end

      def drop_assistant_and_tool_results(messages, assistant_idx)
        # Find all following 'tool' messages that correspond to this assistant's calls.
        # In a standard multi-turn loop, tool results immediately follow the assistant message.
        indices_to_drop = [assistant_idx]
        ((assistant_idx + 1)...messages.size).each do |i|
          break if messages[i][:role] != "tool"

          indices_to_drop << i
        end

        # Return the actual messages for summarization or logging
        dropped_messages = indices_to_drop.map { |i| messages[i] }

        # Delete from highest index to lowest to maintain index stability during deletion
        indices_to_drop.sort.reverse_each { |i| messages.delete_at(i) }

        dropped_messages
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

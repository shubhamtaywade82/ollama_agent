# frozen_string_literal: true

require "json"

require_relative "first_json_object"
require_relative "planner_schema"
require_relative "think_block_stripper"

module OllamaAgent
  module LLM
    # Strict JSON plan extraction from LLM text with bounded retries (no coercion).
    class Planner
      # rubocop:disable Metrics/ParameterLists -- kernel boundary: explicit dependencies
      def initialize(
        llm_client:,
        schema:,
        max_retries: 3,
        think_block_stripper: ThinkBlockStripper,
        max_context_tokens: nil,
        token_counter: OllamaAgent::Context::TokenCounter
      )
        @llm_client = llm_client
        @schema = assert_schema!(schema)
        @max_retries = max_retries.to_i
        @think_block_stripper = think_block_stripper
        @max_context_tokens = max_context_tokens
        @token_counter = token_counter
      end
      # rubocop:enable Metrics/ParameterLists

      # @return [{ plan: Hash }, :invalid_after_retries, :budget_exceeded]
      def plan(prompt:, context:, phase:)
        base_messages = normalize_messages(context)
        return :budget_exceeded if context_over_budget?(base_messages, prompt)

        try_plan_with_retries(initial_chat_messages(base_messages, prompt, phase))
      end

      private

      def try_plan_with_retries(messages)
        (0..@max_retries).each do
          result = consume_llm_attempt(messages)
          return result if plan_success?(result)

          messages = result
        end
        :invalid_after_retries
      end

      def plan_success?(result)
        result.is_a?(Hash) && result.key?(:plan)
      end

      def consume_llm_attempt(messages)
        json_text = json_object_from_llm(messages)
        return append_validation_retry(messages, "no balanced JSON object found") unless json_text

        ok, data = parse_json_object(json_text)
        return append_validation_retry(messages, data) unless ok

        valid, reason = PlannerSchema.validate(data, @schema)
        return { plan: stringify_keys_deep(data) } if valid

        append_validation_retry(messages, reason)
      end

      def json_object_from_llm(messages)
        raw = @llm_client.chat(messages: messages)
        FirstJsonObject.extract(strip_thinking(raw.to_s))
      end

      def assert_schema!(schema)
        raise ArgumentError, "schema must be a Hash" unless schema.is_a?(Hash)

        schema
      end

      def strip_thinking(text)
        mod = @think_block_stripper
        return mod.strip(text) if mod.respond_to?(:strip)

        text
      end

      def context_over_budget?(base_messages, prompt)
        return false if @max_context_tokens.nil?

        total = count_messages_tokens(base_messages) + @token_counter.count(text: prompt.to_s)
        total > @max_context_tokens
      end

      def count_messages_tokens(messages)
        messages.sum do |m|
          @token_counter.count(text: m["content"] || m[:content] || "")
        end
      end

      def normalize_messages(context)
        Array(context).map do |m|
          {
            "role" => (m["role"] || m[:role]).to_s,
            "content" => (m["content"] || m[:content]).to_s
          }
        end
      end

      def initial_chat_messages(base_messages, prompt, phase)
        base_messages.dup << {
          "role" => "user",
          "content" => "phase=#{phase}\n#{prompt}"
        }
      end

      def append_validation_retry(messages, reason)
        messages.dup << {
          "role" => "user",
          "content" => "last attempt failed validation: #{reason}"
        }
      end

      def parse_json_object(json_text)
        [true, JSON.parse(json_text)]
      rescue JSON::ParserError => e
        [false, "JSON parse error: #{e.message}"]
      end

      def stringify_keys_deep(obj)
        case obj
        when Hash
          obj.transform_keys(&:to_s).transform_values { |v| stringify_keys_deep(v) }
        when Array
          obj.map { |v| stringify_keys_deep(v) }
        else
          obj
        end
      end
    end
  end
end

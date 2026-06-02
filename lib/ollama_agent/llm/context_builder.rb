# frozen_string_literal: true

module OllamaAgent
  module LLM
    # Assembles chat messages under strict per-section token budgets (fail closed).
    class ContextBuilder
      DEFAULT_BUDGET = { system: 0.10, history: 0.30, focus: 0.50, buffer: 0.10 }.freeze

      def initialize(max_tokens:, token_counter: OllamaAgent::Context::TokenCounter, budget: {})
        @token_counter = token_counter
        @budget = merge_budget(budget)
        @max_tokens = Integer(max_tokens)
      end

      # @return [Array<Hash>] OpenAI-style messages (+role+, +content+ as strings)
      def build(system:, history:, focus:)
        assert_section_budget!(:system, system)
        assert_section_budget!(:history, history)
        assert_section_budget!(:focus, focus)

        messages = []
        messages << { "role" => "system", "content" => system.to_s } unless system.to_s.empty?
        user_body = join_history_focus(history.to_s, focus.to_s)
        messages << { "role" => "user", "content" => user_body } unless user_body.empty?
        messages
      end

      private

      def merge_budget(raw)
        raise ArgumentError, "budget must be a Hash" unless raw.is_a?(Hash)

        merged = DEFAULT_BUDGET.merge(raw.transform_keys(&:to_sym))
        sum = %i[system history focus buffer].sum { |k| merged.fetch(k) }
        raise ArgumentError, "budget fractions (system+history+focus+buffer) must sum to 1.0" unless (sum - 1.0).abs < 1e-9

        merged
      end

      def assert_section_budget!(section, text)
        fraction = @budget.fetch(section)
        cap = (@max_tokens * fraction).floor
        actual = @token_counter.count(text: text.to_s)
        return if actual <= cap

        raise OllamaAgent::BudgetExceeded,
              "#{section} tokens #{actual} exceed budget cap #{cap} (#{fraction} * #{@max_tokens})"
      end

      def join_history_focus(history, focus)
        return focus if history.empty?

        focus.empty? ? history : "#{history}\n\n#{focus}"
      end
    end
  end
end

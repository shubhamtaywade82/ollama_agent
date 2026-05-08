# frozen_string_literal: true

module OllamaAgent
  class Agent
    # One agent run: budget, loop detection, model round-trips, and tool results.
    class TurnLoop
      require_relative "../runtime/kernel_bridge"

      def initialize(agent)
        @agent = agent
        @kernel_bridge = Runtime::KernelBridge.new(agent)
      end

      def run(messages)
        setup(messages)
        @agent.instance_variable_get(:@max_turns).times { break unless run_one_iteration!(messages) }
        finish(messages)
      end

      private

      def setup(messages)
        @agent.instance_variable_set(:@current_turn, 0)
        @agent.instance_variable_get(:@budget).reset!
        @agent.instance_variable_get(:@loop_detector).reset!
        @agent.instance_variable_get(:@trace_logger)&.start_run(query: messages.last&.fetch(:content, nil))
      end

      # @return [Boolean] false when the outer loop should stop
      # rubocop:disable Naming/PredicateMethod -- imperative step; boolean continues inner loop
      def run_one_iteration!(messages)
        advance_turn_counter_and_budget!
        return false if budget_stopped?

        trimmed = @agent.send(:trimmed_messages_for_chat, messages)
        message = @agent.send(:chat_coordinator).assistant_message(trimmed)
        tool_calls = @agent.send(:tool_calls_from, message)
        @agent.send(:persist_assistant_turn, messages, message)
        return false if tool_calls.empty?

        return false if loop_break?

        @kernel_bridge.append_tool_results(messages: messages, tool_calls: tool_calls)
        true
      end
      # rubocop:enable Naming/PredicateMethod

      def advance_turn_counter_and_budget!
        @agent.instance_variable_set(:@current_turn, @agent.instance_variable_get(:@current_turn) + 1)
        @agent.instance_variable_get(:@budget).record_step!
      end

      def loop_break?
        return false unless @agent.instance_variable_get(:@loop_detector).loop_detected?

        summary = @agent.instance_variable_get(:@loop_detector).loop_summary
        @agent.logger.warn(summary.to_s)
        @agent.instance_variable_get(:@trace_logger)&.loop_detected(summary: summary)
        true
      end

      def budget_stopped?
        budget = @agent.instance_variable_get(:@budget)
        return false unless budget.exceeded?

        reason = budget.exceeded_reason
        @agent.logger.warn("budget exceeded — #{reason}")
        warn_step_hint(budget)
        @agent.instance_variable_get(:@trace_logger)&.budget_exceeded(reason: reason)
        true
      end

      def warn_step_hint(budget)
        return unless budget.steps_exceeded?

        max_turns = @agent.instance_variable_get(:@max_turns)
        @agent.logger.warn(
          "for large repo-wide tasks, raise OLLAMA_AGENT_MAX_TURNS (now #{max_turns}); " \
          "see README \"Agent budget\"."
        )
      end

      def finish(messages)
        @agent.send(:emit_turn_complete, messages)
        @agent.send(:warn_max_turns_if_needed)
      end
    end
  end
end

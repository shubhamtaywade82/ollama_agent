# frozen_string_literal: true

module OllamaAgent
  class Agent
    # One agent run: budget, loop detection, model round-trips, and tool results.
    class TurnLoop
      require_relative "../runtime/kernel_bridge"

      def initialize(max_turns:, budget:, loop_detector:, trace_logger:, context_manager:,
                     chat_coordinator:, hooks:, logger:, kernel_bridge:, session_manager:)
        @max_turns = max_turns
        @budget = budget
        @loop_detector = loop_detector
        @trace_logger = trace_logger
        @context_manager = context_manager
        @chat_coordinator = chat_coordinator
        @hooks = hooks
        @logger = logger
        @kernel_bridge = kernel_bridge
        @session_manager = session_manager
        @current_turn = 0
      end

      def run(messages)
        setup(messages)
        @max_turns.times { break unless run_one_iteration!(messages) }
        finish(messages)
      end

      private

      def setup(messages)
        Console.reset_thinking_session!
        @current_turn = 0
        @budget.reset!
        @loop_detector.reset!
        @trace_logger&.start_run(query: messages.last&.fetch(:content, nil))
      end

      # @return [Boolean] false when the outer loop should stop
      # rubocop:disable Naming/PredicateMethod -- imperative step; boolean continues inner loop
      def run_one_iteration!(messages)
        advance_turn_counter_and_budget!
        return false if budget_stopped?

        trimmed = @context_manager.trim(messages)
        message = @chat_coordinator.assistant_message(trimmed)
        tool_calls = tool_calls_from(message)
        persist_assistant_turn(messages, message)
        return false if tool_calls.empty?

        return false if loop_break?

        @kernel_bridge.append_tool_results(messages: messages, tool_calls: tool_calls)
        true
      end
      # rubocop:enable Naming/PredicateMethod

      def advance_turn_counter_and_budget!
        @current_turn += 1
        @budget.record_step!
      end

      def loop_break?
        return false unless @loop_detector.loop_detected?

        summary = @loop_detector.loop_summary
        @logger.warn(summary.to_s)
        @trace_logger&.loop_detected(summary: summary)
        true
      end

      def budget_stopped?
        return false unless @budget.exceeded?

        reason = @budget.exceeded_reason
        @logger.warn("budget exceeded — #{reason}")
        warn_step_hint
        @trace_logger&.budget_exceeded(reason: reason)
        true
      end

      def warn_step_hint
        return unless @budget.steps_exceeded?

        @logger.warn(
          "for large repo-wide tasks, raise OLLAMA_AGENT_MAX_TURNS (now #{@max_turns}); " \
          "see README \"Agent budget\"."
        )
      end

      def finish(messages)
        emit_turn_complete(messages)
        warn_max_turns_if_needed
      end

      def tool_calls_from(message)
        calls = message.tool_calls || []
        return calls unless calls.empty? && ToolContentParser.enabled?

        ToolContentParser.synthetic_calls(message.content)
      end

      def persist_assistant_turn(messages, message)
        messages << message.to_h
        @session_manager.save_message_to_session(message.to_h)
      end

      def emit_turn_complete(messages)
        @hooks.emit(:on_complete, { messages: messages, turns: @current_turn })
      end

      def warn_max_turns_if_needed
        return unless ENV["OLLAMA_AGENT_DEBUG"] == "1" && @current_turn >= @max_turns

        @logger.warn("maximum tool rounds (#{@max_turns}) reached")
      end
    end
  end
end
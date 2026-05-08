# frozen_string_literal: true

module OllamaAgent
  module ToolRuntime
    # Planner output + phase-scoped tool execution with escalation hooks.
    class Supervisor
      PLANNER_FAILURES = %i[invalid_after_retries budget_exceeded].freeze

      def initialize(
        planner:,
        tool_registry:,
        escalation_callback: nil,
        max_local_attempts: 3
      )
        @planner = planner
        @tool_registry = tool_registry
        @escalation_callback = escalation_callback || proc { :escalated_stub }
        @max_local_attempts = Integer(max_local_attempts)
      end

      # @return [Hash] +:result+, +:escalated+
      def orchestrate(prompt:, context:, phase:)
        state = build_initial_orchestration_state
        @max_local_attempts.times do
          outcome = run_orchestration_attempt!(state, prompt, context, phase)
          return escalate! if outcome == :escalate

          break if outcome
        end
        finalize_orchestration(state)
      end

      private

      def planner_terminal_failure?(plan_out)
        PLANNER_FAILURES.include?(plan_out)
      end

      def escalate!
        @escalation_callback.call
        { result: :escalated, escalated: true }
      end

      def build_initial_orchestration_state
        { last_tool_results: [], last_plan: nil, progress: false }
      end

      def run_orchestration_attempt!(state, prompt, context, phase)
        plan_out = @planner.plan(prompt: prompt, context: context, phase: phase)
        return :escalate if planner_terminal_failure?(plan_out)

        state[:last_plan] = plan_out[:plan]
        results = []
        tool_progress = run_tool_steps(state[:last_plan], phase, results)
        state[:last_tool_results] = results
        state[:progress] = true if tool_progress
        state[:progress]
      end

      def finalize_orchestration(state)
        return escalate! unless state[:progress]

        {
          result: { plan: state[:last_plan], tool_results: state[:last_tool_results] },
          escalated: false
        }
      end

      def run_tool_steps(plan_hash, phase, results)
        extract_steps(plan_hash).reduce(false) do |progressed, step|
          tool_step_progressed?(step, phase, results) || progressed
        end
      end

      def tool_step_progressed?(step, phase, results)
        name = tool_name_from(step)
        return false if name.nil?

        invoke_tool!(name, phase, step, results)
        true
      end

      def tool_name_from(step)
        raw = step["tool"] || step[:tool]
        return nil if raw.nil? || raw.to_s.strip.empty?

        raw.to_s
      end

      def invoke_tool!(name, phase, step, results)
        args = step["args"] || step[:args] || {}
        args = {} unless args.is_a?(Hash)
        res = @tool_registry.invoke(name: name, phase: phase, **symbolize_keys(args))
        raise ToolPhaseError if res == :tool_not_available_in_phase

        results << { tool: name, result: res }
      end

      def extract_steps(plan_hash)
        steps = plan_hash["steps"] || plan_hash[:steps]
        return [] unless steps.is_a?(Array)

        steps
      end

      def symbolize_keys(hash)
        hash.transform_keys(&:to_sym)
      end
    end
  end
end

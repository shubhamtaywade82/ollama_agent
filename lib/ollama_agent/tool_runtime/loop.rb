# frozen_string_literal: true

module OllamaAgent
  module ToolRuntime
    # Think → resolve tool → execute → observe (memory); stops when a tool returns `status: "done"` or max_steps.
    # {#run} returns the last tool result (the object returned from {Executor#execute} on the final step).
    class Loop
      attr_reader :max_steps, :plan_extractor

      alias planner plan_extractor

      # rubocop:disable Metrics/ParameterLists -- runtime wiring matches plan (planner, registry, executor, memory, logger)
      def initialize(registry:, executor:, memory:, logger: nil, max_steps: 10, plan_extractor: nil, planner: nil)
        @plan_extractor = plan_extractor || planner
        raise ArgumentError, "plan_extractor or planner is required" if @plan_extractor.nil?

        @registry = registry
        @executor = executor
        @memory = memory
        @logger = logger
        @max_steps = Integer(max_steps)
      end
      # rubocop:enable Metrics/ParameterLists

      def run(context:)
        steps = 0
        final_result = nil
        Kernel.loop do
          raise MaxStepsExceeded, "max_steps=#{@max_steps} exceeded" if steps >= @max_steps

          thought, action, final_result = plan_and_execute(context)
          record_step(thought: thought, action: action, result: final_result)
          break if terminated?(final_result)

          steps += 1
        end
        final_result
      end

      private

      def plan_and_execute(context)
        thought = @plan_extractor.next_step(context: context, memory: @memory, registry: @registry)
        action = @registry.resolve(thought)
        raise InvalidPlanError, "invalid tool plan: #{thought.inspect}" unless action

        result = @executor.execute(action)
        [thought, action, result]
      end

      def record_step(thought:, action:, result:)
        log_step(thought: thought, action: action, result: result)
        @memory.append(thought: thought, action: action, result: result)
      end

      def terminated?(result)
        return false unless result.is_a?(Hash)

        status = result["status"] || result[:status]
        status.to_s == "done"
      end

      def log_step(thought:, action:, result:)
        return unless @logger.respond_to?(:info)

        tool = action[:tool]
        tool_name = tool.respond_to?(:name) ? tool.name : "?"
        @logger.info("tool_runtime thought=#{thought.inspect} tool=#{tool_name} result=#{result.inspect}")
      end
    end
  end
end

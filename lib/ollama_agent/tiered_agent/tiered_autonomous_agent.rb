# frozen_string_literal: true

require "fileutils"
require "json"

module OllamaAgent
  module TieredAgent
    # Orchestrates a fully autonomous multi-tier execution loop on 8 GB VRAM hardware.
    #
    # The loop executes in five sequential phases per cycle:
    #
    #   1. PLANNING       – Medium (7B) model reads compressed state → selects next tool
    #   2. EXTRACTION     – Small  (3B) model parses tool arguments from natural language
    #   3. EXECUTION      – Ruby runtime invokes the sandboxed system action directly
    #   4. VERIFICATION   – Medium (7B) model cross-checks output against expectations
    #   5. ESCALATION     – Large (14B+) model intervenes after ESCALATION_THRESHOLD failures
    #
    # Models are sequentially evicted from VRAM via the keep_alive option before the
    # next tier loads, staying within the 7.2 GB usable ceiling of an 8 GB GPU.
    class TieredAutonomousAgent
      DEFAULT_MAX_LOOPS         = 50
      ESCALATION_THRESHOLD      = 3

      # @param goal        [String]  objective for the autonomous agent to achieve
      # @param max_loops   [Integer] hard ceiling on execution cycles (default 50)
      # @param keep_alive  [String]  VRAM flush TTL passed to Ollama (default "10s")
      # @param num_ctx     [Integer] context window token cap per inference call (default 4096)
      # @param model_small  [String, nil] override the Small-tier model name
      # @param model_medium [String, nil] override the Medium-tier model name
      # @param model_large  [String, nil] override the Large-tier model name
      def initialize(goal:,
                     max_loops:    DEFAULT_MAX_LOOPS,
                     keep_alive:   VramOptions::DEFAULT_KEEP_ALIVE,
                     num_ctx:      VramOptions::DEFAULT_NUM_CTX,
                     model_small:  nil,
                     model_medium: nil,
                     model_large:  nil)
        @goal       = goal
        @max_loops  = max_loops.to_i.clamp(1, 500)

        vram_opts = VramOptions.build(keep_alive: keep_alive, num_ctx: num_ctx)
        model_overrides = {
          small: model_small,
          medium: model_medium,
          large: model_large
        }.compact

        @client        = build_client
        @phase_runner  = PhaseRunner.new(client: @client, vram_options: vram_opts,
                                         models: model_overrides)
        @tool_executor = ToolExecutor.new
        @state_log     = StateLog.new

        @loop_count = 0
        @consecutive_failures = 0
      end

      # Runs the tiered execution loop until the goal is resolved, the loop limit
      # is reached, or an unrecoverable error occurs.
      def execute_loop!
        while @loop_count < @max_loops
          @loop_count += 1
          puts "\n=== [Execution Cycle ##{@loop_count} / #{@max_loops}] ==="

          plan = run_planning_phase
          puts "[Plan] Rationale: #{plan["rationale"]}"
          puts "[Plan] Invoking Tool: #{plan["tool_call"]}"

          if plan["tool_call"] == "exit_success"
            puts "\n[Termination] Objective successfully resolved after #{@loop_count} cycle(s)."
            return :success
          end

          args              = run_extraction_phase(plan["tool_call"], plan["tool_instructions"])
          execution_output  = @tool_executor.execute(plan["tool_call"], args)
          verification      = run_verification_phase(plan["tool_call"], args, execution_output)

          update_state(plan, verification)

          trigger_escalation_if_needed
        end

        puts "\n[Warning] Maximum loop count (#{@max_loops}) reached without resolution."
        :max_loops_reached
      end

      private

      def run_planning_phase
        @phase_runner.run_planning(goal: @goal, state_log: @state_log)
      end

      def run_extraction_phase(tool_call, tool_instructions)
        @phase_runner.run_extraction(tool_name: tool_call, instructions: tool_instructions)
      end

      def run_verification_phase(tool_call, args, output)
        @phase_runner.run_verification(tool: tool_call, args: args, output: output)
      end

      def update_state(plan, verification)
        if verification["confirmed_success"]
          @consecutive_failures = 0
          @state_log.update_success(plan["tool_call"])
        else
          @consecutive_failures += 1
          @state_log.record_failure(plan["tool_call"], verification["reasons"])
        end
        @state_log.set_variable("last_executed_tool", plan["tool_call"])
      end

      def trigger_escalation_if_needed
        return if @consecutive_failures < ESCALATION_THRESHOLD

        puts "\n[Escalation] #{ESCALATION_THRESHOLD} consecutive failures — " \
             "loading Large model supervisor (CPU spillover mode)..."

        recommendation = @phase_runner.run_escalation(goal: @goal, state_log: @state_log)
        puts "[Supervisor] #{recommendation}"

        @state_log.append_supervisor_intervention(recommendation)
        @consecutive_failures = 0
      end

      def build_client
        require "ollama_client"

        OllamaAgent::OllamaConnection.retry_wrapped_client(
          timeout: 180,
          max_attempts: 3,
          base_url: ENV.fetch("OLLAMA_BASE_URL", nil),
          api_key: ENV.fetch("OLLAMA_API_KEY", nil)
        )
      end
    end
  end
end

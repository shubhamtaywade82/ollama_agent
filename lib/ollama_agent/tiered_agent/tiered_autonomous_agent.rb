# frozen_string_literal: true

require "fileutils"
require "json"

module OllamaAgent
  module TieredAgent
    # Orchestrates a fully autonomous multi-tier execution loop that adapts its
    # model selection and context budget to the available GPU hardware.
    #
    # Startup sequence:
    #   1. Probe VRAM (nvidia-smi / rocm-smi / Apple sysctl) — or use explicit override
    #   2. Select a {HardwareProfile} matching the detected VRAM
    #   3. Print the active profile summary
    #   4. Run the 5-phase loop until goal resolved / loop limit / unrecoverable error
    #
    # The five loop phases (sequential, one model tier in VRAM at a time):
    #
    #   1. PLANNING     – Medium model reads compressed state → selects next tool
    #   2. EXTRACTION   – Small model parses tool arguments from natural language
    #   3. EXECUTION    – Ruby runtime invokes the sandboxed system action directly
    #   4. VERIFICATION – Medium model cross-checks output against expectations
    #   5. ESCALATION   – Large model intervenes after ESCALATION_THRESHOLD failures
    #
    class TieredAutonomousAgent
      DEFAULT_MAX_LOOPS    = 50
      ESCALATION_THRESHOLD = 3

      # @param goal         [String]       objective for the agent to achieve
      # @param max_loops    [Integer]      hard ceiling on execution cycles
      # @param vram_gb      [Numeric, nil] explicit VRAM override; nil → auto-detect
      # @param profile      [Symbol, nil]  explicit profile override (e.g. :performance);
      #                                    takes precedence over vram_gb / auto-detection
      # @param keep_alive   [String, nil]  VRAM flush TTL — overrides the profile default
      # @param num_ctx      [Integer, nil] context window cap — overrides the profile default
      # @param model_small  [String, nil]  Small-tier model name override
      # @param model_medium [String, nil]  Medium-tier model name override
      # @param model_large  [String, nil]  Large-tier model name override
      def initialize(goal:,
                     max_loops:    DEFAULT_MAX_LOOPS,
                     vram_gb:      nil,
                     profile:      nil,
                     keep_alive:   nil,
                     num_ctx:      nil,
                     model_small:  nil,
                     model_medium: nil,
                     model_large:  nil)
        @goal      = goal
        @max_loops = max_loops.to_i.clamp(1, 500)

        @active_profile = resolve_profile(profile, vram_gb)
        print_hardware_banner

        effective_keep_alive = keep_alive || @active_profile.keep_alive
        effective_num_ctx    = num_ctx    || @active_profile.num_ctx

        vram_opts = VramOptions.build(keep_alive: effective_keep_alive, num_ctx: effective_num_ctx)

        model_overrides = {
          small: model_small || @active_profile.model_small,
          medium: model_medium || @active_profile.model_medium,
          large: model_large || @active_profile.model_large
        }

        @client        = build_client
        @phase_runner  = PhaseRunner.new(client: @client, vram_options: vram_opts,
                                         models: model_overrides)
        @tool_executor = ToolExecutor.new
        @state_log     = StateLog.new

        @loop_count           = 0
        @consecutive_failures = 0
      end

      # Runs the tiered execution loop until the goal is resolved, the loop
      # limit is reached, or an unrecoverable error occurs.
      #
      # @return [:success, :max_loops_reached]
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

          args             = run_extraction_phase(plan["tool_call"], plan["tool_instructions"])
          execution_output = @tool_executor.execute(plan["tool_call"], args)
          verification     = run_verification_phase(plan["tool_call"], args, execution_output)

          update_state(plan, verification)
          trigger_escalation_if_needed
        end

        puts "\n[Warning] Maximum loop count (#{@max_loops}) reached without resolution."
        :max_loops_reached
      end

      # The profile selected at initialisation time (exposed for inspection / tests).
      # @return [HardwareProfile::Profile]
      attr_reader :active_profile

      private

      # ---------------------------------------------------------------------------
      # Profile resolution
      # ---------------------------------------------------------------------------

      def resolve_profile(profile_override, vram_gb_override)
        if profile_override
          found = HardwareProfile.find(profile_override)
          unless found
            valid = (HardwareProfile.all_names + [:cloud]).join(", ")
            raise ArgumentError, "Unknown profile #{profile_override.inspect}. Valid profiles: #{valid}"
          end

          return found
        end

        # Cloud auto-detection: skip the local VRAM probe entirely when targeting a
        # remote endpoint. vram_gb_override forces local profile selection even in
        # cloud mode (useful for testing or hybrid setups).
        if vram_gb_override.nil? && HardwareProbe.cloud_mode?
          @cloud_mode = true
          return HardwareProfile::CLOUD_PROFILE
        end

        detected_gb = vram_gb_override || probe_vram
        HardwareProfile.for_vram(detected_gb)
      end

      def probe_vram
        gb = HardwareProbe.detect_vram_gb
        @detected_vram_gb = gb
        gb
      end

      def print_hardware_banner
        if @cloud_mode
          puts "[Hardware] Ollama Cloud / remote inference → Profile: #{@active_profile.label}"
          puts "  Note: Large-tier model (#{@active_profile.model_large}) may need a Pro subscription."
          puts "        Override with --model-large <free-model> if needed."
        else
          vram_str = @detected_vram_gb ? "#{format("%.1f", @detected_vram_gb)} GB VRAM" : "VRAM unknown"
          puts "[Hardware] #{vram_str} → Profile: #{@active_profile.label}"
        end
        puts "  Small:   #{@active_profile.model_small}"
        puts "  Medium:  #{@active_profile.model_medium}"
        puts "  Large:   #{@active_profile.model_large}"
        puts "  Context: #{@active_profile.num_ctx} tokens, keep_alive: #{@active_profile.keep_alive}"
      end

      # ---------------------------------------------------------------------------
      # Execution phases
      # ---------------------------------------------------------------------------

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
             "loading Large-tier supervisor (#{@active_profile.model_large})..."

        recommendation = @phase_runner.run_escalation(goal: @goal, state_log: @state_log)
        puts "[Supervisor] #{recommendation}"

        @state_log.append_supervisor_intervention(recommendation)
        @consecutive_failures = 0
      end

      # ---------------------------------------------------------------------------
      # Client
      # ---------------------------------------------------------------------------

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

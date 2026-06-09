# frozen_string_literal: true

require_relative "tiered_agent/hardware_probe"
require_relative "tiered_agent/hardware_profile"
require_relative "tiered_agent/model_tier"
require_relative "tiered_agent/vram_options"
require_relative "tiered_agent/state_log"
require_relative "tiered_agent/tool_executor"
require_relative "tiered_agent/phase_runner"
require_relative "tiered_agent/tiered_autonomous_agent"

module OllamaAgent
  # Adaptive multi-tier autonomous agent (Small→Medium→Large model cascade).
  #
  # Selects a hardware profile at startup based on detected VRAM (or an explicit
  # --profile / --vram-gb override), then runs the five-phase execution loop with
  # the models and context window size that best match available GPU memory.
  #
  # Entry point:
  #   TieredAgent::TieredAutonomousAgent.new(goal: "...").execute_loop!
  module TieredAgent
  end
end

# frozen_string_literal: true

require_relative "tiered_agent/model_tier"
require_relative "tiered_agent/vram_options"
require_relative "tiered_agent/state_log"
require_relative "tiered_agent/tool_executor"
require_relative "tiered_agent/phase_runner"
require_relative "tiered_agent/tiered_autonomous_agent"

module OllamaAgent
  # 8 GB VRAM-optimised multi-tier autonomous agent (Small→Medium→Large cascade).
  #
  # Entry point:
  #   TieredAgent::TieredAutonomousAgent.new(goal: "...").execute_loop!
  module TieredAgent
  end
end

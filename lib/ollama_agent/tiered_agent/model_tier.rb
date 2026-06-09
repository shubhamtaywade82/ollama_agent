# frozen_string_literal: true

module OllamaAgent
  module TieredAgent
    # Defines the three model tiers used by the 8 GB VRAM swap architecture.
    #
    # Only one tier is resident in GPU memory at a time; models are evicted via
    # keep_alive=0 / short TTL before the next phase loads a different tier.
    module ModelTier
      # ~3.2 GB VRAM — fast parameter extraction and regex-style token processing.
      SMALL  = "llama3.2:3b-instruct-q8_0"

      # ~4.7 GB VRAM — primary orchestration, planning, and verification.
      MEDIUM = "qwen2.5:7b-instruct-q4_K_M"

      # ~5.8 GB weights + RAM spillover — escalation supervisor and deep-reasoning.
      LARGE  = "qwen2.5:14b-instruct-q2_K"

      VRAM_FOOTPRINT = {
        SMALL => "~3.2 GB",
        MEDIUM => "~4.7 GB",
        LARGE => "~5.8 GB (remainder spills to RAM)"
      }.freeze

      ALL = [SMALL, MEDIUM, LARGE].freeze
    end
  end
end

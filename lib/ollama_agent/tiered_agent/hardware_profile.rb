# frozen_string_literal: true

module OllamaAgent
  module TieredAgent
    # Model matrix and inference options for each hardware tier.
    #
    # Profiles are defined in ascending VRAM order. {.for_vram} walks the list
    # from the top and returns the most capable profile whose minimum_vram_gb
    # threshold is satisfied by the detected hardware.
    #
    # Profile layout (all three model slots use sequential VRAM swapping):
    #
    #   Small  → fast parameter extraction         (loaded for Phase 2 only)
    #   Medium → planning + verification            (loaded for Phases 1 and 4)
    #   Large  → escalation supervisor              (loaded only on repeated failure)
    #
    module HardwareProfile
      # Value object for a single hardware tier configuration.
      Profile = Struct.new(
        :name,             # Symbol  — profile identifier
        :label,            # String  — human-readable name
        :minimum_vram_gb,  # Numeric — minimum VRAM to activate this profile
        :description,      # String  — one-line summary
        :model_small,      # String  — Ollama model tag for the Small tier
        :model_medium,     # String  — Ollama model tag for the Medium tier
        :model_large,      # String  — Ollama model tag for the Large tier
        :keep_alive,       # String  — Ollama keep_alive (e.g. "10s", "30s")
        :num_ctx,          # Integer — context window token cap per inference call
        keyword_init: true
      ) do
        def to_h
          super.transform_keys(&:to_s)
        end
      end

      # ---------------------------------------------------------------------------
      # Profile definitions
      # ---------------------------------------------------------------------------
      # Keep-alive is set long enough that repeated calls within a phase do not
      # force a reload, but short enough that the next tier can load without OOM.
      # num_ctx scales with available VRAM — larger windows cost more KV cache.
      # ---------------------------------------------------------------------------

      PROFILES = [
        Profile.new(
          name: :minimal,
          label: "8 GB (Minimal)",
          minimum_vram_gb: 0,
          description: "≤8 GB — 3B/7B-q4/14B-q2 cascade, aggressive VRAM flushing",
          model_small: "llama3.2:3b-instruct-q8_0",
          model_medium: "qwen2.5:7b-instruct-q4_K_M",
          model_large: "qwen2.5:14b-instruct-q2_K",
          keep_alive: "10s",
          num_ctx: 4_096
        ),
        Profile.new(
          name: :standard,
          label: "12 GB (Standard)",
          minimum_vram_gb: 10,
          description: "10–14 GB — 3B/14B-q4/32B-q2 cascade, 8k context",
          model_small: "llama3.2:3b-instruct-q8_0",
          model_medium: "qwen2.5:14b-instruct-q4_K_M",
          model_large: "qwen2.5:32b-instruct-q2_K",
          keep_alive: "20s",
          num_ctx: 8_192
        ),
        Profile.new(
          name: :performance,
          label: "16 GB (Performance)",
          minimum_vram_gb: 14,
          description: "14–22 GB — 7B-q8/14B-q4/32B-q4 cascade, 16k context",
          model_small: "qwen2.5:7b-instruct-q8_0",
          model_medium: "qwen2.5:14b-instruct-q4_K_M",
          model_large: "qwen2.5:32b-instruct-q4_K_M",
          keep_alive: "30s",
          num_ctx: 16_384
        ),
        Profile.new(
          name: :high,
          label: "24 GB (High)",
          minimum_vram_gb: 22,
          description: "22–30 GB — 7B-q8/32B-q4/72B-q2 cascade, 32k context",
          model_small: "qwen2.5:7b-instruct-q8_0",
          model_medium: "qwen2.5:32b-instruct-q4_K_M",
          model_large: "qwen2.5:72b-instruct-q2_K",
          keep_alive: "60s",
          num_ctx: 32_768
        ),
        Profile.new(
          name: :ultra,
          label: "32 GB (Ultra)",
          minimum_vram_gb: 30,
          description: "30–44 GB — 14B-q8/32B-q4/72B-q4 cascade, 32k context",
          model_small: "qwen2.5:14b-instruct-q8_0",
          model_medium: "qwen2.5:32b-instruct-q4_K_M",
          model_large: "qwen2.5:72b-instruct-q4_K_M",
          keep_alive: "120s",
          num_ctx: 32_768
        ),
        Profile.new(
          name: :maximum,
          label: "48+ GB (Maximum)",
          minimum_vram_gb: 44,
          description: "44+ GB — 14B-q8/72B-q4/72B-q8 cascade, 64k context",
          model_small: "qwen2.5:14b-instruct-q8_0",
          model_medium: "qwen2.5:72b-instruct-q4_K_M",
          model_large: "qwen2.5:72b-instruct-q8_0",
          keep_alive: "300s",
          num_ctx: 65_536
        )
      ].freeze

      PROFILE_MAP = PROFILES.to_h { |p| [p.name, p] }.freeze

      # Returns the best-fit profile for the given VRAM amount.
      # Walks profiles from most capable downward; returns the first one whose
      # minimum_vram_gb is satisfied. Falls back to :minimal (minimum_vram_gb = 0).
      #
      # @param vram_gb [Numeric, nil]  nil → conservative :minimal fallback
      # @return [Profile]
      def self.for_vram(vram_gb)
        return PROFILE_MAP[:minimal] if vram_gb.nil?

        gb = vram_gb.to_f
        PROFILES.reverse_each { |p| return p if gb >= p.minimum_vram_gb }
        PROFILE_MAP[:minimal]
      end

      # Looks up a profile by name symbol or string.
      # @param name [Symbol, String]
      # @return [Profile, nil]
      def self.find(name)
        PROFILE_MAP[name.to_sym]
      end

      # All valid profile name symbols, in ascending VRAM order.
      # @return [Array<Symbol>]
      def self.all_names
        PROFILES.map(&:name)
      end

      # Returns a formatted table string for --help / CLI display.
      # @return [String]
      def self.summary_table
        rows = PROFILES.map do |p|
          format("  %-12<name>s  %-22<label>s  %<desc>s",
                 name: p.name, label: p.label, desc: p.description)
        end
        ["Available profiles:", *rows].join("\n")
      end
    end
  end
end

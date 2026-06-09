# frozen_string_literal: true

require "timeout"

module OllamaAgent
  module TieredAgent
    # Detects available GPU VRAM using multiple platform-specific probes.
    #
    # Probe order:
    #   1. NVIDIA  — nvidia-smi (Linux / Windows)
    #   2. AMD     — rocm-smi  (Linux)
    #   3. Apple   — sysctl unified memory heuristic (macOS)
    #   4. nil     — no GPU / CPU-only fallback
    #
    # All probes are run with a short timeout and rescued independently, so a
    # broken or missing tool never crashes the agent startup.
    module HardwareProbe
      PROBE_TIMEOUT_S = 5

      # Returns the best single-GPU VRAM estimate in GB (Float), or nil.
      # For multi-GPU systems the maximum single-device VRAM is returned, because
      # Ollama (without NVLink) loads each model onto a single GPU.
      #
      # @return [Float, nil]
      def self.detect_vram_gb
        nvidia_vram_gb || amd_vram_gb || apple_unified_gb
      rescue StandardError
        nil
      end

      # Returns a human-readable summary string (never raises).
      # @return [String]
      def self.summary
        gb = detect_vram_gb
        gb ? "#{format("%.1f", gb)} GB VRAM detected" : "No GPU detected (CPU-only mode)"
      rescue StandardError
        "VRAM detection unavailable"
      end

      # --- platform probes (module-level private) ---

      # NVIDIA: nvidia-smi returns one line per GPU with MiB total.
      # Example output:
      #   8192
      #   8192
      def self.nvidia_vram_gb
        out = run_cmd("nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null")
        return nil if out.nil?

        mib_values = out.strip.lines.filter_map do |l|
          v = l.strip.to_i
          v.positive? ? v : nil
        end
        return nil if mib_values.empty?

        mib_values.max.to_f / 1024
      end
      private_class_method :nvidia_vram_gb

      # AMD: rocm-smi with --showmeminfo vram
      # Parses lines like:
      #   GPU[0]: VRAM Total Memory (B): 17163091968
      def self.amd_vram_gb
        out = run_cmd("rocm-smi --showmeminfo vram 2>/dev/null")
        return nil if out.nil?

        bytes_values = out.scan(/VRAM Total Memory \(B\):\s*(\d+)/i).flatten.map(&:to_i)
        return nil if bytes_values.empty?

        bytes_values.max.to_f / (1024**3)
      end
      private_class_method :amd_vram_gb

      # Apple Silicon: unified memory is shared between CPU and GPU.
      # We expose 75 % of total RAM as the effective GPU budget, which matches
      # the typical Metal allocation limit on M-series hardware.
      def self.apple_unified_gb
        return nil unless RUBY_PLATFORM.include?("darwin")

        out = run_cmd("sysctl -n hw.memsize 2>/dev/null")
        return nil if out.nil?

        total_bytes = out.strip.to_i
        return nil if total_bytes.zero?

        (total_bytes.to_f / (1024**3)) * 0.75
      end
      private_class_method :apple_unified_gb

      # Runs a shell command with a hard timeout.
      # Returns stdout string on success (exit 0), nil on failure / timeout / missing binary.
      def self.run_cmd(cmd)
        output = Timeout.timeout(PROBE_TIMEOUT_S) { `#{cmd}` }
        $CHILD_STATUS&.success? ? output : nil
      rescue StandardError
        nil
      end
      private_class_method :run_cmd
    end
  end
end

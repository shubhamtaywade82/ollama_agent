# frozen_string_literal: true

require "open3"

module OllamaAgent
  # Resolves ripgrep / grep executables: explicit ENV paths first, then `command -v` (no shell).
  module SearchBackend
    class << self
      def clear_cache!
        mutex.synchronize do
          @rg_resolved = false
          @rg_path = nil
          @grep_resolved = false
          @grep_path = nil
        end
      end

      def rg_executable
        mutex.synchronize do
          return @rg_path if @rg_resolved

          @rg_resolved = true
          @rg_path = resolve_path("OLLAMA_AGENT_RG_PATH", "rg")
        end
      end

      def grep_executable
        mutex.synchronize do
          return @grep_path if @grep_resolved

          @grep_resolved = true
          @grep_path = resolve_path("OLLAMA_AGENT_GREP_PATH", "grep")
        end
      end

      private

      def mutex
        @mutex ||= Mutex.new
      end

      def resolve_path(env_key, binary)
        from_env = ENV.fetch(env_key, nil)
        if from_env && !from_env.to_s.strip.empty?
          expanded = File.expand_path(from_env.to_s.strip)
          return real_executable(expanded) if File.file?(expanded) && File.executable?(expanded)

          debug_warn "#{env_key} does not point to an executable file"
          return nil
        end

        lookup_via_command_v(binary)
      end

      # rubocop:disable Metrics/MethodLength -- small subprocess + realpath branch
      def lookup_via_command_v(binary)
        stdout, status = Open3.capture2("command", "-v", binary)
        unless status.success?
          debug_warn "text search backend #{binary.inspect} not found on PATH"
          return nil
        end

        path = stdout.to_s.strip.split("\n").first
        return nil if path.nil? || path.empty?

        real_executable(path)
      rescue Errno::ENOENT, Errno::ELOOP, Errno::EACCES
        debug_warn "could not resolve #{binary.inspect} (#{$ERROR_INFO.class})"
        nil
      end
      # rubocop:enable Metrics/MethodLength

      def real_executable(path)
        File.realpath(path)
      rescue Errno::ENOENT, Errno::ELOOP, Errno::EACCES
        nil
      end

      def debug_warn(msg)
        warn "ollama_agent: #{msg}" if ENV["OLLAMA_AGENT_DEBUG"] == "1"
      end
    end
  end
end

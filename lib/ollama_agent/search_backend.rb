# frozen_string_literal: true

module OllamaAgent
  # Resolves ripgrep / grep executables: explicit ENV paths first, then PATH scan (no `command` subprocess).
  # PATH scan avoids Errno::ENOENT when /usr/bin is missing from PATH (some IDE/sandbox launches).
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

        lookup_in_path(binary)
      end

      def lookup_in_path(binary)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
          next if dir.empty?

          found = find_executable_in_dir(dir, binary)
          return found if found
        end
        debug_warn "text search backend #{binary.inspect} not found on PATH"
        nil
      end

      def find_executable_in_dir(dir, binary)
        candidate_names_for(binary).each do |name|
          candidate = File.join(dir, name)
          next unless File.file?(candidate) && File.executable?(candidate)

          resolved = real_executable(candidate)
          return resolved if resolved
        end
        nil
      end

      def candidate_names_for(binary)
        names = [binary]
        names << "#{binary}.exe" if Gem.win_platform?
        names
      end

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

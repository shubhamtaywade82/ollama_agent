# frozen_string_literal: true

module OllamaAgent
  # Resolves and normalizes the agent workspace root from explicit config or ENV.
  module AgentRootResolver
    module_function

    # @param explicit [String, nil] path from AgentConfig
    # @param env [Hash] typically ENV
    # @param cwd [String] directory for expanding relative paths
    # @return [String] absolute path (best-effort realpath when the path exists)
    def resolve(explicit, env: ENV, cwd: Dir.pwd)
      raw = explicit
      raw = env.fetch("OLLAMA_AGENT_ROOT", nil) if raw.nil? || raw.to_s.strip.empty?
      raw = cwd if raw.nil? || raw.to_s.strip.empty?

      expanded = File.expand_path(raw.to_s, cwd)
      File.realpath(expanded)
    rescue Errno::ENOENT, Errno::ELOOP, Errno::EACCES, Errno::ENOTDIR
      expanded
    end
  end
end

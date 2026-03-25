# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "securerandom"
require "timeout"

require_relative "argv_interp"
require_relative "delegate_timeout_status"

module OllamaAgent
  module ExternalAgents
    # Runs external CLIs with cwd = project root; argv only (no shell).
    # rubocop:disable Metrics/ModuleLength
    module Runner
      module_function

      DEFAULT_MAX_OUTPUT = 100_000

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/ParameterLists
      def run(agent_def:, root:, executable:, task:, context_summary:, paths:, timeout_sec:, max_output_bytes: nil)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        task_path = nil
        paths = Array(paths).compact.map(&:to_s)
        validate_paths!(root, paths)

        max_b = max_output_bytes || positive_int_env("OLLAMA_AGENT_DELEGATE_MAX_OUTPUT_BYTES", DEFAULT_MAX_OUTPUT)

        handoff = build_handoff(task, context_summary, paths)
        task_path = write_handoff(root, handoff)
        argv = ArgvInterp.expand(
          agent_def["argv"] || [],
          "binary" => executable,
          "task_file" => task_path,
          "root" => root
        )
        return "Error: empty argv for agent #{agent_def["id"]}" if argv.empty?

        out, err, status = capture_with_timeout(argv, root, timeout_sec)
        code = status&.exitstatus
        log_delegate_event(
          agent_def: agent_def,
          root: root,
          argv: argv,
          timeout_sec: timeout_sec,
          exit_code: code,
          duration_ms: elapsed_ms(started_at)
        )
        combined = "exit:#{code}\n"
        combined << "stdout:\n#{truncate(out.to_s, max_b)}\n"
        combined << "stderr:\n#{truncate(err.to_s, max_b)}\n"
        combined
      ensure
        File.unlink(task_path) if task_path && File.file?(task_path)
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/ParameterLists

      def interpolate_argv(tokens, subs)
        ArgvInterp.expand(tokens, subs)
      end

      def validate_paths!(root, paths)
        root = File.expand_path(root)
        paths.each do |p|
          next if p.to_s.strip.empty?

          abs = File.expand_path(p, root)
          unless abs == root || abs.start_with?(root + File::SEPARATOR)
            raise ArgumentError, "path outside project root: #{p}"
          end
        end
      end

      def build_handoff(task, context_summary, paths)
        parts = []
        parts << "Task:\n#{task.to_s.strip}"
        parts << "\nContext:\n#{context_summary.to_s.strip}" unless context_summary.to_s.strip.empty?
        parts << "\nRelevant paths (under project root):\n#{paths.map { |p| "- #{p}" }.join("\n")}" unless paths.empty?
        parts.join("\n")
      end

      def write_handoff(root, text)
        dir = File.join(root, ".ollama_agent")
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "handoff-#{SecureRandom.hex(8)}.txt")
        File.write(path, text, encoding: Encoding::UTF_8)
        path
      end

      def capture_with_timeout(argv, root, timeout_sec)
        Timeout.timeout(timeout_sec) do
          Open3.capture3(*argv, chdir: root)
        end
      rescue Timeout::Error
        ["", "ollama_agent: delegate timed out after #{timeout_sec}s", DelegateTimeoutStatus.new]
      end

      def truncate(str, max_bytes)
        s = str.to_s
        return s if s.bytesize <= max_bytes

        "#{s.byteslice(0, max_bytes)}…\n[truncated: output exceeded #{max_bytes} bytes]"
      end

      def positive_int_env(key, default)
        v = ENV.fetch(key, nil)
        return default if v.nil? || v.to_s.strip.empty?

        Integer(v)
      rescue ArgumentError, TypeError
        default
      end

      # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
      def log_delegate_event(agent_def:, root:, argv:, timeout_sec:, exit_code:, duration_ms:)
        return unless delegate_log_enabled?

        payload = {
          event: "delegate_to_agent",
          agent_id: agent_def["id"].to_s,
          cwd: root.to_s,
          argv: argv,
          timeout_seconds: timeout_sec,
          exit_code: exit_code,
          duration_ms: duration_ms,
          env_keys: delegate_env_keys(agent_def)
        }
        warn("ollama_agent_delegate: #{JSON.generate(payload)}")
      rescue StandardError
        nil
      end
      # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

      def delegate_log_enabled?
        ENV.fetch("OLLAMA_AGENT_DELEGATE_LOG", "0").to_s == "1" || ENV.fetch("OLLAMA_AGENT_DEBUG", "0").to_s == "1"
      end

      def delegate_env_keys(agent_def)
        keys = []
        env_key = agent_def["env_path"].to_s
        keys << env_key unless env_key.empty?
        keys.concat(ENV.keys.grep(/\AOLLAMA_AGENT_/))
        keys.uniq.sort
      end

      def elapsed_ms(started_at)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end

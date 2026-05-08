# frozen_string_literal: true

require_relative "../errors"
require_relative "../llm/anthropic_client"
require_relative "argv_interp"
require_relative "delegate_logger"
require_relative "delegate_timeout_status"
require_relative "env_helpers"
require_relative "path_validator"

module OllamaAgent
  module ExternalAgents
    # Delegates tasks to Anthropic via {LLM::AnthropicClient} (HTTPS only; no host shell-out).
    module Runner
      DEFAULT_MAX_OUTPUT = 100_000

      class << self
        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists, Lint/UnusedMethodArgument
        def run(agent_def:, root:, executable:, task:, context_summary:, paths:, timeout_sec:, max_output_bytes: nil)
          api_key = ENV.fetch("ANTHROPIC_API_KEY", "").strip
          if api_key.empty?
            raise AnthropicAPIError,
                  "ANTHROPIC_API_KEY is not set; external agent delegation requires a configured API key."
          end

          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          paths = Array(paths).compact.map(&:to_s)
          PathValidator.validate_within_root!(root, paths)

          max_b = max_output_bytes || EnvHelpers.env_positive_int(
            "OLLAMA_AGENT_DELEGATE_MAX_OUTPUT_BYTES",
            DEFAULT_MAX_OUTPUT
          )

          handoff = build_handoff(task, context_summary, paths)
          model = agent_def["model"] || ENV.fetch("OLLAMA_AGENT_ANTHROPIC_MODEL", "claude-opus-4-7")
          client = LLM::AnthropicClient.new(api_key: api_key, model: model.to_s, timeout_seconds: timeout_sec)
          reply = client.chat(messages: [{ role: "user", content: handoff }], max_tokens: 8192)

          DelegateLogger.log_delegate_event(
            {
              event: "delegate_to_agent",
              agent_id: agent_def["id"].to_s,
              cwd: root.to_s,
              argv: ["POST", LLM::AnthropicClient::API_URL, model.to_s],
              timeout_seconds: timeout_sec,
              exit_code: 0,
              duration_ms: elapsed_ms(started_at),
              env_keys: delegate_env_keys(agent_def)
            }
          )

          combined = +"exit:0\n"
          combined << "stdout:\n#{truncate(reply[:content].to_s, max_b)}\n"
          combined << "stderr:\n\n"
          combined
        end
        # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists, Lint/UnusedMethodArgument

        def interpolate_argv(tokens, subs)
          ArgvInterp.expand(tokens, subs)
        end

        def build_handoff(task, context_summary, paths)
          parts = []
          parts << "Task:\n#{task.to_s.strip}"
          parts << "\nContext:\n#{context_summary.to_s.strip}" unless context_summary.to_s.strip.empty?
          unless paths.empty?
            path_lines = paths.map { |p| "- #{p}" }.join("\n")
            parts << "\nRelevant paths (under project root):\n#{path_lines}"
          end
          parts.join
        end

        def truncate(str, max_bytes)
          s = str.to_s
          return s if s.bytesize <= max_bytes

          "#{s.byteslice(0, max_bytes)}…\n[truncated: output exceeded #{max_bytes} bytes]"
        end

        def delegate_env_keys(agent_def)
          keys = []
          env_key = agent_def["env_path"].to_s
          keys << env_key unless env_key.empty?
          keys << "ANTHROPIC_API_KEY"
          keys.concat(ENV.keys.grep(/\AOLLAMA_AGENT_/))
          keys.uniq.sort
        end

        def elapsed_ms(started_at)
          ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round
        end
      end
    end
  end
end

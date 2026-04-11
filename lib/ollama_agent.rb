# frozen_string_literal: true

require_relative "ollama_agent/version"

env_before_ollama_client = ENV.to_hash
require "ollama_client"
require_relative "ollama_agent/global_dotenv"
OllamaAgent::GlobalDotenv.reconcile_after_ollama_client!(env_before_ollama_client)
require_relative "ollama_agent/ollama_chat_thinking_stream"
require_relative "ollama_agent/console"
require_relative "ollama_agent/tools/registry"
require_relative "ollama_agent/tools/base"
require_relative "ollama_agent/streaming/hooks"
require_relative "ollama_agent/streaming/console_streamer"
require_relative "ollama_agent/resilience/retry_middleware"
require_relative "ollama_agent/resilience/audit_logger"
require_relative "ollama_agent/context/token_counter"
require_relative "ollama_agent/context/manager"
require_relative "ollama_agent/session/session"
require_relative "ollama_agent/session/store"

# ── v2 core runtime kernel ───────────────────────────────────────────────────
require_relative "ollama_agent/core/action_envelope"
require_relative "ollama_agent/core/budget"
require_relative "ollama_agent/core/loop_detector"
require_relative "ollama_agent/core/schema_validator"
require_relative "ollama_agent/core/trace_logger"

# ── v2 provider abstraction ──────────────────────────────────────────────────
require_relative "ollama_agent/providers/registry"

# ── v2 memory tiers ──────────────────────────────────────────────────────────
require_relative "ollama_agent/memory/manager"

# ── v2 runtime layer ─────────────────────────────────────────────────────────
require_relative "ollama_agent/runtime/approval_gate"
require_relative "ollama_agent/runtime/permissions"
require_relative "ollama_agent/runtime/policies"
require_relative "ollama_agent/runtime/sandbox"

# ── v2 indexing layer ─────────────────────────────────────────────────────────
require_relative "ollama_agent/indexing/repo_scanner"
require_relative "ollama_agent/indexing/file_indexer"
require_relative "ollama_agent/indexing/context_packer"
require_relative "ollama_agent/indexing/diff_summarizer"

# ── v2 plugin architecture ───────────────────────────────────────────────────
require_relative "ollama_agent/plugins/registry"
require_relative "ollama_agent/plugins/loader"

# ── v2 enhanced tools ────────────────────────────────────────────────────────
require_relative "ollama_agent/tools/shell_tools"
require_relative "ollama_agent/tools/git_tools"
require_relative "ollama_agent/tools/http_tools"
require_relative "ollama_agent/tools/memory_tools"

require_relative "ollama_agent/agent"
require_relative "ollama_agent/runner"
require_relative "ollama_agent/cli"

# Public namespace for the universal AI operator runtime + developer shell.
module OllamaAgent
  class Error < StandardError; end

  class ConfigurationError < Error; end

  def self.gem_root
    File.expand_path("..", __dir__)
  end

  # Convenience: build a runner with the recommended defaults.
  #
  # @example
  #   OllamaAgent.run("Refactor the auth module", root: "/my/project")
  def self.run(query, root: Dir.pwd, **kwargs)
    Runner.build(root: root, **kwargs).run(query)
  end
end

require_relative "ollama_agent/tool_runtime"
require_relative "ollama_agent/self_improvement"

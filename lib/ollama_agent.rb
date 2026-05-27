# frozen_string_literal: true

require "logger"

require_relative "ollama_agent/version"
require_relative "ollama_agent/errors"

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
require_relative "ollama_agent/state/tree_digest"
require_relative "ollama_agent/state/workspace_fingerprint"
require_relative "ollama_agent/state/reentry_packet"
require_relative "ollama_agent/state/git_changed_paths"
require_relative "ollama_agent/state/ast_summarizer"
require_relative "ollama_agent/state/reconciler"
require_relative "ollama_agent/security/resource_guard"
require_relative "ollama_agent/security/ownership_index"
require_relative "ollama_agent/security/ownership_compiler"
require_relative "ollama_agent/llm/think_block_stripper"
require_relative "ollama_agent/llm/planner"
require_relative "ollama_agent/llm/context_builder"
require_relative "ollama_agent/llm/anthropic_client"
require_relative "ollama_agent/llm/cloud_fallback_router"
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
require_relative "ollama_agent/runtime/execution_mode"
require_relative "ollama_agent/runtime/criticality_policy"
require_relative "ollama_agent/runtime/execution_context"
require_relative "ollama_agent/runtime/logical_clock"
require_relative "ollama_agent/runtime/database_registry"
require_relative "ollama_agent/runtime/cost_ledger"
require_relative "ollama_agent/runtime/kernel_health"
require_relative "ollama_agent/runtime/event_store"
require_relative "ollama_agent/runtime/wal"
require_relative "ollama_agent/runtime/fencing_allocator"
require_relative "ollama_agent/runtime/cas_guard"
require_relative "ollama_agent/runtime/atomic_mutator"
require_relative "ollama_agent/runtime/lock_manager"
require_relative "ollama_agent/runtime/intent_reservation"
require_relative "ollama_agent/runtime/saga_state"
require_relative "ollama_agent/runtime/saga_coordinator"
require_relative "ollama_agent/runtime/mutation_classifier"
require_relative "ollama_agent/runtime/isolated_validator"
require_relative "ollama_agent/runtime/post_condition_verifier"
require_relative "ollama_agent/runtime/file_atomic_swap"
require_relative "ollama_agent/runtime/blob_store"
require_relative "ollama_agent/runtime/compactor"
require_relative "ollama_agent/runtime/compactor_runner"
require_relative "ollama_agent/runtime/permission_bridge"
require_relative "ollama_agent/runtime/compensation_manifest"
require_relative "ollama_agent/runtime/compensation_engine"
require_relative "ollama_agent/runtime/saga_recovery_daemon"
require_relative "ollama_agent/runtime/integration_queue"
require_relative "ollama_agent/runtime/execution_manifest"
require_relative "ollama_agent/runtime/kernel_feature"
require_relative "ollama_agent/runtime/intent_translator"
require_relative "ollama_agent/runtime/kernel_bridge"
require_relative "ollama_agent/runtime/kernel_pipeline"
require_relative "ollama_agent/runtime/workspace_wal_replay"
require_relative "ollama_agent/runtime/rollback_signals"
require_relative "ollama_agent/runtime/kernel_event_logger"
require_relative "ollama_agent/runtime/kernel_tool_seed"

# ── v2 indexing layer ─────────────────────────────────────────────────────────
require_relative "ollama_agent/indexing/repo_scanner"
require_relative "ollama_agent/indexing/file_indexer"
require_relative "ollama_agent/indexing/context_packer"
require_relative "ollama_agent/indexing/diff_summarizer"

# ── topology compiler (E11a IR + symbol graph) ────────────────────────────────
require_relative "ollama_agent/topology/ir/node"
require_relative "ollama_agent/topology/ir/class_node"
require_relative "ollama_agent/topology/ir/module_node"
require_relative "ollama_agent/topology/ir/concern_node"
require_relative "ollama_agent/topology/ir/event_publisher_node"
require_relative "ollama_agent/topology/ir/worker_node"
require_relative "ollama_agent/topology/ir/route_node"
require_relative "ollama_agent/topology/ir/callback_node"
require_relative "ollama_agent/topology/signature_normalizer"
require_relative "ollama_agent/topology/symbol_identity"
require_relative "ollama_agent/topology/symbol_graph"
require_relative "ollama_agent/topology/staged_graph"
require_relative "ollama_agent/topology/zeitwerk_inflector"
require_relative "ollama_agent/topology/extractors/ruby_semantic_extractor"
require_relative "ollama_agent/topology/linker"

# ── integration synthesis (E12; committed topology as source of truth) ───────
require_relative "ollama_agent/synthesis/integration_scan"
require_relative "ollama_agent/synthesis/integration_extractor"
require_relative "ollama_agent/synthesis/event_schema_registry"
require_relative "ollama_agent/synthesis/route_synthesizer"
require_relative "ollama_agent/synthesis/sidekiq_synthesizer"

# ── v2 plugin architecture ───────────────────────────────────────────────────
require_relative "ollama_agent/plugins/registry"
require_relative "ollama_agent/plugins/loader"

# ── v2 enhanced tools ────────────────────────────────────────────────────────
require_relative "ollama_agent/tools/shell_tools"
require_relative "ollama_agent/tools/git_tools"
require_relative "ollama_agent/tools/http_tools"
require_relative "ollama_agent/tools/memory_tools"
require_relative "ollama_agent/tools/filesystem_explorer"
require_relative "ollama_agent/tools/safe_calculator"

# ── deterministic skill system (JSON-contract pipelines) ─────────────────────
require_relative "ollama_agent/skills/json_extractor"
require_relative "ollama_agent/skills/llm_client"
require_relative "ollama_agent/skills/registry"
require_relative "ollama_agent/skills/base"
require_relative "ollama_agent/skills/runner"
require_relative "ollama_agent/skills/architecture_refactorer"
require_relative "ollama_agent/skills/performance_optimizer"
require_relative "ollama_agent/skills/debug_engineer"
require_relative "ollama_agent/skills/feature_builder"

require_relative "ollama_agent/agent"
require_relative "ollama_agent/runner"
require_relative "ollama_agent/cli"

# Public namespace for the universal AI operator runtime + developer shell.
module OllamaAgent
  class << self
    attr_writer :logger
  end

  def self.logger
    @logger ||= Logger.new($stderr, progname: "ollama_agent", level: Logger::INFO)
  end

  def self.gem_root
    File.expand_path("..", __dir__)
  end

  # Convenience: build a runner with the recommended defaults.
  #
  # @example
  #   OllamaAgent.run("Refactor the auth module", root: "/my/project")
  def self.run(query, root: Dir.pwd, **)
    Runner.build(root: root, **).run(query)
  end

  # Registers default phase-scoped kernel tools on a {OllamaAgent::ToolRuntime::ToolRegistry}.
  def self.seed_kernel_tools(registry:, pipeline:)
    Runtime::KernelToolSeed.seed(tool_registry: registry, kernel_pipeline: pipeline)
  end
end

require_relative "ollama_agent/tool_runtime"
require_relative "ollama_agent/self_improvement"

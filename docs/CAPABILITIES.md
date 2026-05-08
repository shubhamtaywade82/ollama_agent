# ollama_agent capabilities (post-kernel)

## Overview

`ollama_agent` is a Ruby gem and CLI that drives a **tool-calling agent** against a chat model (default: local **Ollama**; optional OpenAI / Anthropic providers). The model proposes **function calls**; the runtime validates arguments and executes tools under a **workspace root** (file IO, search, patches, optional shell and delegation). An optional **kernel runtime** (`OLLAMA_AGENT_KERNEL`) adds SQLite-backed sagas, a mutation WAL, ownership gates, replayable mutations, and operator-facing health and cost persistence—without changing the high-level “ask the model, run tools” loop.

---

## Core agent capabilities

| Capability | Status | Primary code | Related docs |
|------------|--------|--------------|--------------|
| Multi-turn chat with tool loop | stable | `lib/ollama_agent/agent.rb`, `lib/ollama_agent/agent/turn_loop.rb`, `lib/ollama_agent/agent/chat_coordinator.rb` | `docs/USAGE.md`, `README.md` |
| Ollama `/api/chat` (blocking + streaming hooks) | stable | `lib/ollama_agent/ollama_connection.rb`, `lib/ollama_agent/providers/ollama.rb` | `README.md` |
| OpenAI / Anthropic providers + router | stable / opt-in keys | `lib/ollama_agent/providers/*.rb` | `README.md`, `docs/USAGE.md` |
| Built-in tools: `read_file`, `search_code`, `list_files`, `edit_file`, `write_file`, optional `run_shell` | stable | `lib/ollama_agent/tools/built_in_schemas.rb`, `lib/ollama_agent/sandboxed_tools.rb` | `README.md` |
| **Prism Ruby index** (`search_code` modes: class, module, constant, method) | stable | `lib/ollama_agent/ruby_index*.rb`, `lib/ollama_agent/ruby_index_tool_support.rb` | `lib/ollama_agent/tools/built_in_schemas.rb` (schema text) |
| Prompt **skills** (bundled + extra paths) | stable | `lib/ollama_agent/prompt_skills.rb`, `lib/ollama_agent/agent_prompt.rb` | `README.md`, `docs/USAGE.md` |
| Deterministic **JSON skills** CLI (`skill list|run|pipeline`) | stable | `lib/ollama_agent/cli/skill_command.rb`, `lib/ollama_agent/skills/` | `README.md`, `docs/CLI.md` |
| **Sessions** (save / resume transcript) | stable | `lib/ollama_agent/session/store.rb`, `lib/ollama_agent/cli.rb` (`sessions`) | `README.md` |
| **TUI** + line REPL | stable | `lib/ollama_agent/cli/tui_repl.rb`, `lib/ollama_agent/cli/repl.rb` | `README.md`, `docs/CLI.md` |
| Orchestrator tools + `orchestrate` | opt-in | `lib/ollama_agent/external_agents.rb`, `lib/ollama_agent/cli.rb` | `README.md` |
| Permissions / policies / approval gate | stable | `lib/ollama_agent/runtime/permissions.rb`, `lib/ollama_agent/runtime/policies.rb`, `lib/ollama_agent/runtime/approval_gate.rb` | `README.md`, `docs/USAGE.md` |
| Loop detection, budget, context trim | stable | `lib/ollama_agent/core/loop_detector.rb`, `lib/ollama_agent/context/manager.rb` | `README.md` |
| Self-review / improve (sandbox modes) | stable | `lib/ollama_agent/self_improvement/`, `lib/ollama_agent/cli.rb` | `README.md`, `docs/CLI.md` |
| Plugins | experimental | `lib/ollama_agent/plugins/loader.rb` | `README.md` |

---

## Kernel runtime capabilities

Enabled when `OLLAMA_AGENT_KERNEL` is `true` or `shadow` (`lib/ollama_agent/runtime/kernel_feature.rb`). Tool subset routed through the pipeline is configurable via `OLLAMA_AGENT_KERNEL_PIPELINE_TOOLS` (see `lib/ollama_agent/runtime/kernel_bridge.rb`).

| Capability | Status | Primary code | Related docs |
|------------|--------|--------------|--------------|
| Saga FSM (reserved → locked → mutations_applied → verified → integration_queued → committed / compensated) | stable (flagged) | `lib/ollama_agent/runtime/saga_state.rb`, `lib/ollama_agent/runtime/saga_coordinator.rb`, `lib/ollama_agent/runtime/kernel_pipeline.rb` | `docs/agile/release_rollout_runbook.md`, `docs/OPERATIONS.md` |
| **Shadow** execution (WAL + saga without real byte swap for configured ops) | opt-in | `lib/ollama_agent/runtime/execution_mode.rb`, `lib/ollama_agent/runtime/kernel_pipeline.rb` | `docs/agile/release_rollout_runbook.md` |
| Atomic mutations (CAS, blobs, compensation rows) | stable (flagged) | `lib/ollama_agent/runtime/atomic_mutator.rb`, `lib/ollama_agent/runtime/blob_store.rb`, `lib/ollama_agent/runtime/compensation_engine.rb` | `docs/OPERATIONS.md` |
| Ownership index + compiler (`owners.yml`) | opt-in file | `lib/ollama_agent/security/ownership_compiler.rb`, `lib/ollama_agent/security/ownership_index.rb`, `config/ollama_agent/owners.yml` | `docs/USAGE.md`, `docs/OPERATIONS.md` |
| Permission bridge (legacy vs kernel) | stable (flagged) | `lib/ollama_agent/runtime/permission_bridge.rb` | `README.md` |
| Recovery / leases / fencing | stable (flagged) | `lib/ollama_agent/runtime/saga_recovery_daemon.rb`, `lib/ollama_agent/runtime/lock_manager.rb`, `lib/ollama_agent/runtime/fencing_allocator.rb` | `docs/OPERATIONS.md` |
| Post-mutation validation (isolated validator optional Docker) | experimental / CI-gated | `lib/ollama_agent/runtime/isolated_validator.rb` | `docs/agile/docker_spec_activation.md` |
| Mutation WAL + global replay | stable (flagged) | `lib/ollama_agent/runtime/wal.rb`, `lib/ollama_agent/runtime/event_store.rb`, `lib/ollama_agent/runtime/workspace_wal_replay.rb` | `docs/USAGE.md`, `docs/OPERATIONS.md` |
| **LLM boundary** (no wall-clock on saga path; cloud router uses separate clock for breakers only) | stable | `lib/ollama_agent/llm/cloud_fallback_router.rb`, `lib/ollama_agent/llm/anthropic_client.rb` | `docs/USAGE.md` |
| Topology (IR, symbol graph, linker) | stable library | `lib/ollama_agent/topology/` | `docs/new_features_plan_v2.md` |
| Integration synthesis | stable library | `lib/ollama_agent/synthesis/` | `docs/new_features_plan_v2.md` |
| Kernel event JSON logging | stable | `lib/ollama_agent/runtime/kernel_event_logger.rb` | `docs/OPERATIONS.md` |

---

## Operational tooling

| Capability | Status | Primary code | Related docs |
|------------|--------|--------------|--------------|
| Feature flag `OLLAMA_AGENT_KERNEL` (`false` / `shadow` / `true`) | stable | `lib/ollama_agent/runtime/kernel_feature.rb` | `docs/agile/release_rollout_runbook.md`, `docs/OPERATIONS.md` |
| **Kernel health** CLI (`ollama_agent kernel health`) | stable | `lib/ollama_agent/cli/health_command.rb`, `lib/ollama_agent/runtime/kernel_health.rb` | `docs/CLI.md`, `docs/OPERATIONS.md` |
| **Schema migrations** (versioned SQL under `db/ollama_agent/migrations/`) | stable | `lib/ollama_agent/runtime/schema_migrator.rb`, `lib/ollama_agent/runtime/database_registry.rb` | `docs/OPERATIONS.md` |
| **Cost ledger** (runtime SQLite `cost_ledger` + `CloudFallbackRouter`) | stable | `lib/ollama_agent/runtime/cost_ledger.rb`, `lib/ollama_agent/llm/cloud_fallback_router.rb` | `docs/USAGE.md` |
| **RollbackSignals** (in-memory thresholds for operators) | stable | `lib/ollama_agent/runtime/rollback_signals.rb` | `docs/OPERATIONS.md` |
| Compaction + archive DB | opt-in operator job | `lib/ollama_agent/runtime/compactor.rb`, `lib/ollama_agent/runtime/compactor_runner.rb` | `docs/agile/release_rollout_runbook.md`, `docs/OPERATIONS.md` |
| Audit / trace hooks | opt-in env | `lib/ollama_agent/resilience/audit_logger.rb`, `lib/ollama_agent/core/trace_logger.rb` | `README.md` |

---

## Test coverage summary (684 examples)

The suite is **RSpec** under `spec/`. Approximate layers:

| Layer | Paths | What is exercised |
|-------|--------|---------------------|
| Agent + tools | `spec/ollama_agent/agent_spec.rb`, `spec/ollama_agent/sandboxed_tools_spec.rb`, tool schema specs | Chat loop, tool execution, path sandbox, read-only mode |
| Providers / LLM | `spec/ollama_agent/providers/`, `spec/ollama_agent/llm/` | Ollama/OpenAI/Anthropic adapters, retry + streaming client, cloud router + cost ledger |
| Kernel runtime | `spec/ollama_agent/runtime/` | Database registry + migrations, saga, WAL, bridge, pipeline, health, blob store, compactor, permissions |
| Integration | `spec/integration/` | Legacy path without kernel; optional real-Ollama smoke (`OLLAMA_HOST`) |
| Self-improvement / CLI | `spec/ollama_agent/self_improvement/`, CLI-related specs where present | Modes, harness behavior |

Counts are from `bundle exec rspec` (includes pending examples for Docker and opt-in real LLM).

---

## Related documentation

| Document | Role |
|----------|------|
| `README.md` | Install, quick usage, kernel summary |
| `docs/CLI.md` | Subcommand and flag reference |
| `docs/USAGE.md` | End-user workflows |
| `docs/OPERATIONS.md` | Rollout, incidents, SQL, compaction, health |
| `docs/agile/release_rollout_runbook.md` | Kernel rollout stages (cross-ref operations) |
| `docs/new_features_plan_v2.md` | Design backlog and architecture notes |
| `docs/agile/docker_spec_activation.md` | Isolated validator / Docker |

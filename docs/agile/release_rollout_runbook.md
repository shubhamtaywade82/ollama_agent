# Runtime Kernel Release and Rollout Runbook

**Operator deep-dive:** incident SQL, health JSON fields, compaction tuning, and cost-ledger queries live in **`docs/OPERATIONS.md`** (keep this runbook for stage gates; use OPERATIONS for on-call).

## Pre-Release Checklist

1. M1-M6 milestone acceptance criteria verified.
2. Kernel-off regression suite is green.
3. Deterministic replay fixtures pass in CI.
4. Recovery duplicate-prevention tests pass.
5. Security path ownership tests pass.

## Rollout Stages

1. Default off (`OLLAMA_AGENT_KERNEL` unset).
2. Shadow mode on selected repos for telemetry only.
3. Opt-in enablement for pilot repos.
4. Broader enablement after stability window.
5. Default on after post-rollout metrics are within limits.

## Rollback Triggers

- Replay mismatch rate above threshold.
- Duplicate recovery signal observed.
- Elevated mutation failure rates.
- Validator provenance mismatch.

## Rollback Procedure

1. Disable `OLLAMA_AGENT_KERNEL`.
2. Restart long-running sessions.
3. Confirm kernel-off parity checks pass.
4. Open incident with captured replay and recovery event traces.

## Post-Release Validation

- Confirm no increase in kernel-off workflow regressions.
- Confirm event stream contains lock/CAS/saga/replay telemetry.
- Validate escalation breaker behavior under synthetic stress tests.

## Kernel cutover checklist

**Prerequisites**

- `sqlite3` gem present; versioned migrations under `db/ollama_agent/migrations/` applied on first kernel open by `OllamaAgent::Runtime::SchemaMigrator` (see `docs/OPERATIONS.md` pre-flight).
- `config/ollama_agent/owners.yml` compiled successfully (or repo-local copy under the workspace); ownership index matches the tree you intend to mutate.
- Docker available on hosts running E7 isolated-validator specs (`DOCKER_AVAILABLE=true` when executing those examples).
- `ANTHROPIC_API_KEY` set anywhere external agent delegation (`ExternalAgents::Runner`) is used; absence raises `AnthropicAPIError`.

**Feature flag**

- `OLLAMA_AGENT_KERNEL=true` routes `write_file`, `edit_file`, `apply_patch`, `delete_file`, `rename_file`, and `move_file` (or the subset configured in `OLLAMA_AGENT_KERNEL_PIPELINE_TOOLS`) through `Runtime::KernelPipeline`.
- `OLLAMA_AGENT_KERNEL=shadow` enables the same bridge routing as `true`, but the pipeline runs in **shadow** execution mode (see below): saga + WAL + observability + compensation rows are recorded, **without** mutating workspace file bytes for `atomic_write` / WAL-only shadow paths for delete/rename.
- Unset or `false` keeps `KernelBridge` on the legacy `append_tool_results` path (no saga rows for tool execution).

## Shadow mode (`OLLAMA_AGENT_KERNEL=shadow`)

Use shadow on selected hosts or CI smoke jobs before turning the kernel on for real writes:

```bash
OLLAMA_AGENT_KERNEL=shadow ruby -S ollama_agent …
```

Behavior (see `Runtime::ExecutionMode::SHADOW`, `Runtime::KernelFeature.shadow?`, `Runtime::KernelPipeline`):

- Full saga FSM (locks → mutations_applied → verified → integration_queued → committed).
- **No** `AtomicMutator` disk swap for content writes; mutation intent is still appended to the WAL with content-addressed `sha256` blobs (replay semantics preserved).
- `CompensationManifest` rows use `op = shadow` for the pre-state snapshot associated with the shadowed mutation.
- Post-condition checks still run against the **unchanged** workspace tree (validators must tolerate shadow semantics).
- Observability hooks (`:on_saga_start`, `:on_saga_advance`, `:on_saga_compensate`, `:on_kernel_pipeline_complete`) still fire when a `hooks` subscriber is wired.

## Rollback signal table (`Runtime::RollbackSignals`)

Pure in-memory helper for operators (e.g. pipe counters to Prometheus). Rolling window: last **60 logical-epoch ticks** via `tick(epoch:)`; samples carry optional `epoch` in `record` payloads.

| Signal / event | Default threshold | Suggested action |
|----------------|-------------------|------------------|
| `:replay_determinism_violation` | ≥ 1 / window | Freeze rollout; inspect WAL replay fixtures; compare `WorkspaceFingerprint` hashes |
| `:recovery_duplicate` | ≥ 1 / window | Investigate saga recovery / intent reservation collisions |
| `:mutation_failure` + `:mutation_success` (rate) | failure rate ≥ 0.1 | Treat as elevated mutation failure rate; scale traffic or disable kernel |
| `:validator_integrity_mismatch` | ≥ 1 / window | Treat as provenance / validator mismatch; disable isolated validator requirement or rotate image |

Call `RollbackSignals#should_rollback?` after feeding events; when `trigger` is true, execute the **Rollback Procedure** above.

## Observability hook subscription example

```ruby
signals = OllamaAgent::Runtime::RollbackSignals.new
logger = OllamaAgent::Runtime::KernelEventLogger.new(
  logger: OllamaAgent.logger,
  rollback_signals: signals
)
OllamaAgent::Runtime::KernelPipelineAssembly.build_for_workspace(
  workspace_root: project_root,
  hooks: logger
)
# Drive logical epochs from your orchestration clock (tests call tick explicitly):
signals.tick(epoch: 1)
```

Alternatively pass `logger:` into `build_for_workspace` to auto-wrap `KernelEventLogger` when you do **not** pass custom `hooks:`.

**Monitoring / inspection keys**

- **Saga state:** `SELECT state, terminal, manifest_id FROM sagas` in `runtime.db` (under workspace `.ollama_agent/kernel/runtime.db`).
- **Lease holders:** `locks` table (`scope`, `holder`, `expires_at_epoch`, `fencing_token`) for active scope leases.
- **Recovery lease occupancy:** `recovery_leases` rows (`manifest_id`, `holder`, `expires_at_epoch`) — non-expired rows indicate an in-flight or stuck recovery claim.
- **Integration queue:** `integration_queue` status transitions (`pending` → `claimed` → `done`) after successful pipeline commits.

## Compaction (bounded `runtime.db` / `event_store.db`)

- Run **`OllamaAgent::Runtime::Compactor`** from a supervisor or job loop using the same **logical epoch** source as sagas (never `Time.now` inside the compactor). Defaults retain ~`100_000` epochs of history; tune `retention_epochs` per repo churn.
- **Suggested schedule:** compact at least once per **10k–50k logical epochs** on busy repos, or nightly for low-volume pilots. Wire **`CompactorRunner`** with `interval_epochs:` so the caller’s `tick(current_epoch:)` decides when to invoke `compact`.
- After compaction, spot-check `event_store_archive.db` under `.ollama_agent/kernel/` and confirm active (`terminal = 0`) sagas still replay from `event_store.db`.

## Permission unification migration

1. Land **`config/ollama_agent/owners.yml`** in pilot repos before enabling `OLLAMA_AGENT_KERNEL=true` so `PermissionBridge` can evaluate ownership + criticality consistently.
2. Watch logs for `permission bridge:` warnings/errors (legacy vs kernel divergence); resolve by tightening **`Permissions`** profiles or ownership rules until divergence stops.
3. Use **`OllamaAgent::PermissionConflictError`** from `#allow_mutation?` in integration tests to catch mismatches before rollout widens.
4. Kernel-off workloads remain on legacy **`Permissions` / `Policies`** only until the flag is flipped.

**Rollback**

- Set `OLLAMA_AGENT_KERNEL=false` (or unset), restart sessions, and confirm kernel-off parity tests stay green before deeper incident response.

# ollama_agent operations runbook

Operator-focused: kernel rollout, health, SQLite, compaction, incidents. Complements `docs/agile/release_rollout_runbook.md` (milestones and stage narrative); **this file** is the **incident + SQL + tooling** reference.

---

## Pre-flight checklist

| Check | How |
|-------|-----|
| Ruby and gem | `ruby -v` ≥ 3.2; `ollama_agent` / `bundle exec` resolves `sqlite3` gem (runtime dependency). |
| Kernel schema | On first kernel open, `lib/ollama_agent/runtime/schema_migrator.rb` applies `db/ollama_agent/migrations/*.sql` to `.ollama_agent/kernel/event_store.db` and `runtime.db` (`lib/ollama_agent/runtime/database_registry.rb`). No manual `schema.sql` apply. |
| `owners.yml` | Repo should ship `config/ollama_agent/owners.yml` (or workspace copy). Compile path: `lib/ollama_agent/security/ownership_compiler.rb` → `Security::OwnershipIndex`. Validate prefixes cover paths you intend to mutate. |
| Docker | Required only for **E7 isolated validator** flows and specs that tag Docker (`DOCKER_AVAILABLE=true`). See `docs/agile/docker_spec_activation.md`. |
| Env: Ollama | `OLLAMA_HOST` for remote/local Ollama URL when not default. |
| Env: kernel | `OLLAMA_AGENT_KERNEL` unset / `false` / `shadow` / `true`. See `lib/ollama_agent/runtime/kernel_feature.rb`. |
| Env: pipeline tool subset | Optional `OLLAMA_AGENT_KERNEL_PIPELINE_TOOLS` (comma list) parsed in `lib/ollama_agent/runtime/kernel_bridge.rb`. |
| Env: Anthropic escalation | `ANTHROPIC_API_KEY` when using cloud escalation path (`lib/ollama_agent/llm/anthropic_client.rb`). Router: `lib/ollama_agent/llm/cloud_fallback_router.rb`. |
| Health smoke | `bundle exec ollama_agent kernel health --root "$REPO"` → exit `0` before widening traffic. |

---

## Deployment phases (off → shadow → opt-in → default-on)

| Phase | Flag / condition | Go / no-go |
|-------|------------------|------------|
| Off | `OLLAMA_AGENT_KERNEL` unset or `false` | Baseline: kernel-off CI green (`spec/integration/legacy_path_smoke_spec.rb` and agent specs). |
| Shadow | `OLLAMA_AGENT_KERNEL=shadow` | **Go:** health OK; WAL + saga events appear; no unexpected legacy-only failures. **No-go:** replay tests fail or health `unhealthy`. |
| Opt-in pilot | `true` on selected repos | **Go:** shadow stable for window; `owners.yml` present; operators trained on SQL below. **No-go:** elevated rollback signals (`RollbackSignals`). |
| Default-on | org policy sets `true` broadly | **Go:** post-pilot metrics within limits documented in `docs/agile/release_rollout_runbook.md`. **No-go:** incident rate on replay / recovery / mutation failure. |

---

## RollbackSignals: signal → meaning → action → investigation

Implementation: `lib/ollama_agent/runtime/rollback_signals.rb`. Window: **60 logical epochs** (`WINDOW_TICKS`); samples may carry `epoch` in `record` payload. Query **application logs** (not SQLite) unless you also emit these to metrics.

| Event key | Meaning | Suggested action | Investigate |
|-----------|---------|------------------|-------------|
| `:replay_determinism_violation` | WAL replay or digest check disagreed with expected deterministic outcome | Freeze rollout; capture manifest id and WAL slice | Re-run `WorkspaceWalReplay` (`lib/ollama_agent/runtime/workspace_wal_replay.rb`) on a **copy** of tree + `.ollama_agent/kernel`. Compare blob hashes in WAL payloads to `blob_store` files. Check for extractor or gem version drift in the environment that produced the WAL. |
| `:recovery_duplicate` | Duplicate or conflicting recovery work detected (threshold counts events/min) | Ensure **single** recovery supervisor per workspace; check lease semantics | `sqlite3 .ollama_agent/kernel/runtime.db 'SELECT manifest_id, holder, acquired_at_epoch, expires_at_epoch FROM recovery_leases ORDER BY expires_at_epoch DESC LIMIT 50;'` Overlapping holders on same manifest → multiple daemons. |
| `:mutation_failure` / `:mutation_success` | Rate of failed vs succeeded kernel mutations | Inspect saga terminal reasons; ownership conflicts | `SELECT state, terminal, manifest_id, metadata FROM sagas ORDER BY last_transition_at_epoch DESC LIMIT 50;` Non-terminal stuck states → `saga_transitions` for that `manifest_id`. |
| `:validator_integrity_mismatch` | Isolated validator image / digest mismatch | Rebuild pinned image; disable validator gate temporarily only if policy allows | Validator spec logs; compare configured digest vs `docker images`. |

Programmatic check: `RollbackSignals#should_rollback?` → `{ trigger:, reasons: }`. When `KernelEventLogger` is wired with `rollback_signals:`, pipeline completion may record mutation success/failure (`lib/ollama_agent/runtime/kernel_event_logger.rb`).

---

## Common incidents (detail)

### Replay determinism violation

**Meaning:** deterministic replay of mutation WAL does not reproduce expected tree state (or fingerprint mismatch after replay).

**Investigate:**

1. Copy workspace + `.ollama_agent/kernel/` to a safe path.
2. Run replay API: `OllamaAgent::Runtime::WorkspaceWalReplay` with `event_store_db_path` pointing at `event_store.db` and `blob_store_kernel_dir` at kernel dir (`lib/ollama_agent/runtime/workspace_wal_replay.rb`).
3. Diff tree; locate first diverging `events.id` via `SELECT id, manifest_id, kind, length(payload) FROM events WHERE kind = 'mutation' ORDER BY id`.
4. Check `payload` JSON `op` (`atomic_write`, `delete_file`, `rename_file`) and `sha256` presence for writes.

### Recovery duplicate

**Meaning:** more than one recovery attempt is racing (or lease TTL wrong).

**Investigate:** `recovery_leases` query above; grep logs for `SagaRecoveryDaemon` / recovery (class under `lib/ollama_agent/runtime/saga_recovery_daemon.rb`).

### Mutation failure rate spike

**Meaning:** `mutation_failure` count vs successes crosses `mutation_failure_rate` threshold (default `0.1` in `RollbackSignals::DEFAULT_THRESHOLDS`).

**Investigate:** sagas in non-terminal states; `compensations` unapplied rows:

```sql
SELECT COUNT(*) FROM compensations WHERE applied = 0;
```

Ownership denials: logs from `PermissionBridge` (`lib/ollama_agent/runtime/permission_bridge.rb`).

### Validator integrity mismatch

**Meaning:** container image or digest used by `IsolatedValidator` no longer matches expected provenance.

**Action:** Pin and rebuild image; re-run validator specs with `DOCKER_AVAILABLE=true`. Do not “fix” by disabling validation in production without risk acceptance.

---

## DB compaction

**Type:** logical-epoch driven only (`Compactor#compact(current_epoch:)`). **Do not** pass wall-clock as the epoch source for production orchestration.

**Classes:** `lib/ollama_agent/runtime/compactor.rb`, `lib/ollama_agent/runtime/compactor_runner.rb`.

**Retention:** constructor `retention_epochs:` (default `100_000`). Cutoff = `current_epoch - retention_epochs`. Older **terminal** saga rows and transitions may be pruned; WAL events older than cutoff are **archived** to `.ollama_agent/kernel/event_store_archive.db` (`EVENT_ARCHIVE_BASENAME`).

**When to run:** high churn workspaces: run every **10k–50k** logical epochs, or on a schedule derived from your orchestration clock. Low volume: nightly may suffice.

**After run:** spot-check archive DB size; confirm non-terminal sagas still replay from primary `event_store.db` (see `docs/agile/release_rollout_runbook.md` compaction section).

---

## Health check JSON (`kernel health`)

Producer: `lib/ollama_agent/runtime/kernel_health.rb`.

**Top-level `status`:**

- **`ok`:** event store + runtime SQLite respond; blob dir writable; schema versions on disk match applied migrations; rollback signals (if passed into checker—CLI does **not** wire them) absent from CLI path.
- **`degraded`:** schema version mismatch between migrator files and `schema_migrations` tables, **or** optional rollback-signal trigger when wired.
- **`unhealthy`:** DB probe or blob probe failed.

**Checks map keys:** `:event_store`, `:runtime`, `:blob_store`, `:schema_migrations`, optionally `:rollback_signals`. Each value is `{ ok: bool, detail: ... }`.

---

## Rollback procedure (kernel → off)

1. Set `OLLAMA_AGENT_KERNEL=false` or **unset** (see `KernelFeature.enabled?`).
2. **Restart** long-running agents, workers, and REPLs (env is process-local).
3. Run kernel-off regression tests and smoke `ask` on a canary repo.
4. Keep `.ollama_agent/kernel/` on disk for forensics; do not delete until postmortem complete.

Legacy path does **not** create kernel DBs for normal tool use (`spec/integration/legacy_path_smoke_spec.rb`).

---

## Logs and JSON event schema (`KernelEventLogger`)

Class: `lib/ollama_agent/runtime/kernel_event_logger.rb`.

Each `emit(event, payload)` writes **one JSON object per line** at **info** level, with keys (omitted if nil):

| Field | Typical source |
|-------|----------------|
| `ts_epoch` | payload `epoch` or monotonic clock |
| `event` | event name string |
| `manifest_id` | saga / pipeline manifest |
| `state` | saga state |
| `result` | pipeline result symbol string |
| `error` | error string |
| `kind` | intent / tool kind |
| `scopes` | scope list |
| `reason` | transition reason |
| `intent_hash` | idempotency key |

**Grep examples:**

```bash
rg '"event":"on_kernel_pipeline_complete"' .ollama_agent/logs
rg '"result":"error"' .ollama_agent/logs
```

Wire logger as in `docs/agile/release_rollout_runbook.md` (observability example).

---

## Cost and escalation (operator)

- **Cost ledger table:** `cost_ledger` in `runtime.db` (migration `db/ollama_agent/migrations/0002_cost_ledger.sql`).
- **Query cumulative cost per manifest:**

```sql
SELECT manifest_id, SUM(cost_usd) AS total
FROM cost_ledger
GROUP BY manifest_id
ORDER BY total DESC
LIMIT 20;
```

- **Router:** `CloudFallbackRouter` uses persisted totals when `cost_ledger:` is configured (`lib/ollama_agent/llm/cloud_fallback_router.rb`).

---

## Related documents

- `docs/agile/release_rollout_runbook.md` — stage checklist, shadow semantics, hook wiring.
- `docs/CLI.md` — `kernel health` syntax.
- `docs/CAPABILITIES.md` — capability matrix.
- `docs/USAGE.md` — user-facing enablement and tutorials.

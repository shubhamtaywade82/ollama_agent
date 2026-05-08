# Runtime Kernel Release and Rollout Runbook

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

- `sqlite3` gem present and `db/ollama_agent/schema.sql` applied on first kernel open under `.ollama_agent/kernel/`.
- `config/ollama_agent/owners.yml` compiled successfully (or repo-local copy under the workspace); ownership index matches the tree you intend to mutate.
- Docker available on hosts running E7 isolated-validator specs (`DOCKER_AVAILABLE=true` when executing those examples).
- `ANTHROPIC_API_KEY` set anywhere external agent delegation (`ExternalAgents::Runner`) is used; absence raises `AnthropicAPIError`.

**Feature flag**

- `OLLAMA_AGENT_KERNEL=true` routes `write_file` (and any tools listed in `OLLAMA_AGENT_KERNEL_PIPELINE_TOOLS`, default `write_file`) through `Runtime::KernelPipeline`.
- Unset or `false` keeps `KernelBridge` on the legacy `append_tool_results` path (no saga rows for tool execution).

**Monitoring / inspection keys**

- **Saga state:** `SELECT state, terminal, manifest_id FROM sagas` in `runtime.db` (under workspace `.ollama_agent/kernel/runtime.db`).
- **Lease holders:** `locks` table (`scope`, `holder`, `expires_at_epoch`, `fencing_token`) for active scope leases.
- **Recovery lease occupancy:** `recovery_leases` rows (`manifest_id`, `holder`, `expires_at_epoch`) — non-expired rows indicate an in-flight or stuck recovery claim.
- **Integration queue:** `integration_queue` status transitions (`pending` → `claimed` → `done`) after successful pipeline commits.

**Rollback**

- Set `OLLAMA_AGENT_KERNEL=false` (or unset), restart sessions, and confirm kernel-off parity tests stay green before deeper incident response.

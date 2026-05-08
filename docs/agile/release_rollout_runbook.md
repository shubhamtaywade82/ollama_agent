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

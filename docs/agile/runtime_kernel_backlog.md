# Runtime Kernel Backlog

This backlog operationalizes `docs/new_features_plan_v2.md` into deliverable
Agile slices. It is implementation-facing and intended for direct issue import.

## Epic E1: Storage Kernel

Stories:

1. Create storage layout contract for `runtime.db` and `event_store.db`.
2. Add append-only mutation event API with deterministic sequence semantics.
3. Add replay reader that reconstructs deterministic workspace state.

Acceptance:

- Event order is stable and deterministic for the same input sequence.
- Replay output hash matches the original execution hash.

## Epic E2: Workspace Identity and Lineage

Stories:

1. Define canonical fingerprint inputs and ordering contract.
2. Add execution manifest with parent linkage.
3. Enforce replay rejection on fingerprint mismatch.

Acceptance:

- Equivalent workspace trees produce identical fingerprints.
- Replay on mismatched identity fails closed.

## Epic E3: Ownership and Security

Stories:

1. Add `owners.yml` schema and compiler validation.
2. Implement longest-prefix ownership index.
3. Enforce path traversal and symlink protections at runtime boundary.

Acceptance:

- Unauthorized mutations are rejected.
- Path traversal and symlink race attempts are blocked.

## Epic E4: Atomic Mutation (CAS)

Stories:

1. Implement atomic write strategy with parent fsync semantics.
2. Add CAS precondition checks for pre-hash and fencing token.
3. Add idempotent intent hashing for replay no-op behavior.

Acceptance:

- Crash between write and rename does not corrupt target file.
- Duplicate replay with same intent hash is safely ignored.

## Epic E5: Locking and Intent Reservation

Stories:

1. Add lease-based lock records with expiration.
2. Implement deterministic lock acquisition ordering.
3. Add pre-flight intent reservation conflict checks.

Acceptance:

- Lock contention does not deadlock under fuzz/concurrency tests.
- Expired leases cannot authorize stale mutation attempts.

## Epic E6: Saga Coordinator

Stories:

1. Implement saga FSM states and transitions with checkpoints.
2. Validate lease heartbeat on every transition.
3. Seal terminal manifests to prevent post-commit mutation.

Acceptance:

- Saga recovery is exactly-once after crash.
- Terminal state blocks further mutations.

## Epic E7: Isolated Validator

Stories:

1. Add isolated command validation policy (array exec).
2. Capture validator provenance (image digest) in execution records.
3. Integrate post-condition verification gates.

Acceptance:

- Shell interpolation is not used in validation command path.
- Validation provenance is recorded and queryable.

## Epic E8: Compensation and Recovery

Stories:

1. Implement content-addressed compensation snapshot storage.
2. Add compensation engine using atomic mutator path.
3. Add exclusive recovery lease and duplicate-recovery prevention.

Acceptance:

- Corrupted compensation payload fails integrity checks.
- Concurrent recovery workers cannot double-compensate.

## Epic E9: LLM Boundary

Stories:

1. Add strict planner output schema contract and coercion path.
2. Add think-block sanitization before JSON extraction.
3. Enforce bounded planner budgets and hard-fail behavior.

Acceptance:

- Invalid planner output retries and escalates deterministically.
- Budget overflows do not silently truncate behavior.

## Epic E10: Cloud Escalation and Re-entry

Stories:

1. Implement direct API fallback router for escalation.
2. Add re-entry packet builder with bounded semantic context.
3. Reconcile post-escalation workspace delta and resume local planning.

Acceptance:

- Escalation respects depth, cost, and time circuit-breaker limits.
- Local planner can resume from reconciled post-state.

## Epic E11: Topology Compiler

Stories:

1. Add typed semantic IR and symbol identity model.
2. Implement staged and committed graph promotion.
3. Add incremental invalidation by reverse dependency closure.

Acceptance:

- Multi-origin class reopening yields one stable symbol identity.
- Syntax failures stay staged and do not poison committed graph.

## Epic E12: Integration Synthesis

Stories:

1. Add runtime-derived integration extractor from topology graph.
2. Add route and worker synthesis modules.
3. Add event schema validation gates.

Acceptance:

- Synthesized integrations match reference fixtures.
- Unknown event payload schema fails validation.

## Epic E13: Existing Runtime Integration

Stories:

1. Add feature-flagged kernel route in turn loop/runtime edge.
2. Preserve kernel-off behavior parity.
3. Capture kernel-on observability events and mutation records.

Acceptance:

- Existing behavior remains stable with kernel disabled.
- Kernel-enabled path records all mutation operations.

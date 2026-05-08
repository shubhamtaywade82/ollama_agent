# OllamaAgent Runtime Kernel Plan (v2)

This document is a delivery-focused rewrite of `docs/new_features_plan.md`.
It does not change the architecture. It clarifies execution order, acceptance
gates, and rollout controls so implementation can proceed with lower ambiguity.

## 1) Canonical Status

- Canonical implementation plan: `docs/new_features_plan_v2.md` (this file)
- Source ideation history: `docs/new_features.md`, `docs/new_features copy.md`
- Namespace decision remains unchanged: all components stay under `OllamaAgent::*`

## 2) Frozen Architecture (No Functional Changes)

The architecture remains exactly as agreed:

- `lib/ollama_agent/runtime/` for storage, mutation, locking, saga, manifests
- `lib/ollama_agent/state/` for fingerprinting, reconciliation, re-entry packet
- `lib/ollama_agent/security/` for owners compiler/index and path guardrails
- `lib/ollama_agent/llm/` for planner, context builder, fallback, supervision
- `lib/ollama_agent/topology/` for symbol graph, typed IR, linker pipeline
- `lib/ollama_agent/synthesis/` for runtime-derived route/job/event synthesis

## 3) Included Feature Checklist (Nothing Dropped)

This checklist explicitly tracks all critical primitives already present in the
iterative design rounds and expected in implementation:

- [ ] Split SQLite kernel (`runtime.db`, `event_store.db`)
- [ ] WAL/event store with deterministic replay
- [ ] Fencing allocator and lease-aware mutation controls
- [ ] Canonicalization with schema-aware semantics
- [ ] Workspace fingerprint and lineage manifest chain
- [ ] Owners graph compiler + LPM prefix authorization
- [ ] Realpath/inode/path traversal hardening
- [ ] Atomic mutator (temp write -> fsync -> rename -> fsync parent)
- [ ] CAS guard (`expected_pre_hash`, `fencing_token`, `intent_hash`)
- [ ] Lock manager with deadlock-safe acquisition ordering
- [ ] Intent reservation and pre-flight conflict checks
- [ ] Saga coordinator FSM + checkpointing + terminal sealing
- [ ] Compensation engine with content-addressed blob snapshots
- [ ] Recovery daemon with exclusive transactional recovery lease
- [ ] Isolated validator with array-exec command policy
- [ ] Post-condition verification in deterministic phases
- [ ] Planner JSON contracts and strict schema coercion
- [ ] Think-tag sanitization and escalation circuit breakers
- [ ] Cloud fallback via direct Anthropic API client (no shell-out)
- [ ] Re-entry packet with bounded semantic context
- [ ] Symbol graph with typed semantic IR and multi-pass linker
- [ ] Staged vs committed topology promotion
- [ ] Runtime-derived integration extraction/synthesis
- [ ] Existing runtime bridge behind `OLLAMA_AGENT_KERNEL=true`

## 4) Milestones and Exit Criteria

### M1: Storage + Identity Foundation

Scope:

- E1 Storage Kernel
- E2 Workspace Identity and Lineage

Exit criteria:

- Replay of captured WAL reproduces identical workspace tree hash
- Identical input tree yields identical fingerprint across machines
- Fingerprint mismatch on replay fails hard and blocks execution

### M2: Secure Atomic Mutation Boundary

Scope:

- E3 Ownership and Security
- E4 Atomic Mutation
- E5 Locking and Intent Reservation

Exit criteria:

- Unauthorized writes rejected by ownership and path guards
- Kill during mutation does not produce partial on-disk state
- Stale fences/leases rejected consistently under concurrency
- Lock-order fuzz test shows no deadlock across high contention

### M3: Saga Lifecycle and Recovery

Scope:

- E6 Saga Coordinator
- E7 Isolated Validator
- E8 Compensation and Recovery

Exit criteria:

- Reserve -> Lock -> Mutate -> Verify -> Commit/Compensate is durable
- Kill -9 mid-saga recovers exactly once with no double-apply behavior
- Corrupt compensation blob raises integrity fault and halts rollback
- Terminal manifests reject any post-terminal mutation

### M4: LLM Boundary and Controlled Escalation

Scope:

- E9 LLM Boundary
- E10 Cloud Escalation and Re-entry

Exit criteria:

- Invalid planner JSON retries and escalates as defined
- Budget overflow fails closed instead of truncating silently
- Escalation depth/cost/time breakers enforced deterministically
- Re-entry packet resumes local planning from post-state safely

### M5: Topology Compiler

Scope:

- E11 Topology Compiler

Exit criteria:

- Multi-origin class/module reopening resolves to stable symbol identity
- Concern inclusion and route-worker extraction are deterministic
- Malformed files remain in staged graph and do not poison committed graph
- Incremental invalidation affects only true dependency closure

### M6: Synthesis + Runtime Bridge

Scope:

- E12 Integration Synthesis
- E13 Existing Runtime Integration

Exit criteria:

- Synthesized integrations match golden reference behavior
- Kernel-off mode preserves current behavior
- Kernel-on mode records all mutations in runtime storage path
- No regression in existing test suite when feature flag is off

## 5) Verification Matrix (Required for Each Milestone)

- Unit tests for each new primitive and guard clause behavior
- Property tests for canonicalization/idempotency invariants
- Concurrency tests for lock leasing/fencing race conditions
- Fault-injection tests (kill/power-loss points around write boundaries)
- Replay tests for deterministic state reconstruction
- Security tests for path traversal, symlink swap, and prefix edge cases

Global CI gates:

- Tests pass
- Lint passes
- Type checks pass where applicable
- Build/package checks pass

## 6) Rollout and Safety Controls

- Feature gate: `OLLAMA_AGENT_KERNEL=true`
- Rollout sequence:
  1. kernel disabled by default
  2. shadow execution for observability only
  3. limited opt-in repos
  4. default-on after stability window
- Automatic rollback triggers:
  - replay determinism violation
  - recovery duplicate execution signal
  - elevated mutation failure rate
  - validator integrity mismatch

## 7) Runtime Observability (Minimum)

Capture structured events for:

- lock acquisition/release and lease renewal
- CAS precondition pass/fail reason
- saga state transitions and checkpoint commits
- validator execution details (image digest, command policy)
- escalation attempts and breaker outcomes
- replay operations and determinism checks

## 8) Suggested Branching and Delivery Slice

- Primary branch: `feature/runtime-kernel`
- Keep work in thin vertical slices, one acceptance outcome per PR
- Prioritize M1 and M2 before any planner/escalation coupling
- Preserve compatibility with existing branch work (`feature/add-skills`)

## 9) Decision Register (Architecture Preserved)

This section exists to prevent future ambiguity while preserving current design.
No decisions are changed here; this is tracking only.

- ADR-001: single namespace (`OllamaAgent::*`)
- ADR-002: deterministic storage-first architecture
- ADR-003: saga coordinator for multi-step mutation workflows
- ADR-004: direct API fallback (no CLI shell delegation)
- ADR-005: topology compiler as runtime truth for integration synthesis

## 10) Definition of Done (Project-Level)

The kernel rollout is complete when:

- all milestone exit criteria are green
- feature-flag-off behavior remains stable
- deterministic replay and recovery hold under fault injection
- ownership and mutation boundaries pass adversarial security tests
- synthesis outputs are reproducible and validated against references

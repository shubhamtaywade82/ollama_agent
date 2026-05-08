# Sprint 0 Setup

Sprint 0 objective: establish guardrails, quality gates, and execution scaffolding
before delivering runtime-kernel functional slices.

## Scope

- Definition of Ready and Definition of Done
- ADR lock for kernel architecture decisions
- Delivery risk register baseline
- Deterministic test harness scaffolding

## Definition of Ready (DoR)

A story is ready when:

1. Acceptance criteria are explicit and testable.
2. Security implications are stated.
3. Determinism/replay impact is identified.
4. Rollback behavior is defined.
5. Kernel-off compatibility impact is stated.

## Definition of Done (DoD)

A story is done when:

1. Tests pass locally and in CI.
2. Lint is green.
3. Feature flag behavior is verified for both off and on paths.
4. Observability events are present for relevant state transitions.
5. Documentation is updated.

## ADR Freeze (Kernel)

- ADR-001: single namespace under `OllamaAgent::*`
- ADR-002: storage-first deterministic runtime
- ADR-003: saga-based orchestration boundary
- ADR-004: direct API fallback, no shell delegation
- ADR-005: topology compiler as synthesis source of truth

## Sprint 0 Deliverables

- Backlog: `docs/agile/runtime_kernel_backlog.md`
- Risks: `docs/agile/runtime_kernel_risk_register.md`
- Test harness: `spec/support/runtime_kernel_harness.rb`
- Sprint map: `docs/agile/sprint_execution_map.md`

## Exit Criteria

- Team has import-ready epic/story definitions.
- Risk register has owner + mitigation for each high-risk item.
- Harness helpers exist for deterministic and recovery-oriented specs.

---
name: ruby-code-review-levels
description: >
  Deterministic 5-level Ruby/Rails PR review checklist for production risk and architectural depth.
---

# Skill: Ruby Code Review Levels (Production-Oriented)

Use this skill when the user asks for a Ruby (Rails API system) code review, refactor guidance, or PR feedback. The goal is to catch failure modes before they ship—not just fix style.

## How to use

For each review, walk levels in order and produce findings grouped by level. Apply these gates:

- Reject immediately if Level 2 fails (logic/edge-case correctness).
- Reject immediately if Level 4 violates system invariants (idempotency, determinism, state correctness).
- Reject immediately if Level 5 lacks required safety controls (observability + external/API safety + graceful failure).
- Otherwise, accept with Level 1/3 improvements if they are non-blocking.

## Level 1 — Syntax & Style Review (Mechanical)

Objective: enforce Ruby idioms, readability, and consistency.

Checks:
- Project RuboCop compliance using the repo’s configuration (not “default” relaxed rules).
- Naming clarity: no generic `data`, `obj`, `thing`, `tmp`; purpose-named identifiers.
- Ruby idioms: prefer `&&`/`||` appropriately, avoid `present?`/Rails-only helpers in hot paths, avoid awkward defensive `nil` checks when Ruby truthiness is sufficient.
- No dead code / no commented-out blocks.
- Method size: aim for small methods (roughly <= 10–15 LOC); split larger logic into intention-revealing private methods.

W5H (required for non-trivial changes):
- What: what does this code do?
- Why: why is this approach needed here?
- Where: where does this belong (controller/model/service/pattern)?
- When: when does it run (sync vs async, request vs background)?
- How it fails: what are the failure modes and what happens next?

## Level 2 — Correctness & Edge Case Review (Logic)

Objective: ensure correct behavior for realistic inputs and boundary conditions.

Mandatory checks:
- Nil handling is explicit and intentional (no accidental `nil` propagation).
- Boundaries: empty collections, zero values, missing keys, unexpected formats.
- Determinism: same inputs should produce the same outputs (especially for decision logic).
- Numeric safety: for floats/rounding, ensure the behavior is stable and documented.
- Time/zone correctness: use the correct time source (avoid mixing app time and system time incorrectly).
- Idempotency guards (where relevant): avoid double-processing, double-exits, duplicate updates.
- Validate invariants before doing work (e.g., existence checks, “state is allowed” checks).

Questions:
- What if upstream data is stale/incomplete?
- What if state already changed between decision and action?
- Are there hidden assumptions about ordering or concurrency?

## Level 3 — Design & Abstraction Review (Structure)

Objective: ensure boundaries are real and abstractions are earned.

Rules:
- SRP: each unit has one reason to change.
- Don’t add useless service objects that just proxy model calls.
- Put domain logic with models (or dedicated POROs) and keep controllers thin.
- Extract shared logic across strategies instead of duplicating it with small variations.
- Avoid “fake polymorphism”: only abstract when it reduces duplication or clarifies invariants.

Review heuristics:
- Is the abstraction describing a real concept (e.g., `Position`, `Policy`, `Validator`)?
- Where should this logic live: model, service (orchestrator), or PORO (calculation/logic)?
- Are naming and ownership clear enough that a future developer can extend it safely?

## Level 4 — System & Architectural Review (Integrity)

Objective: ensure correctness under load, failures, and concurrency.

Focus:
- Deterministic flows: event-driven or async sequences should be explicit.
- Idempotency at system boundaries: prevent duplicate side effects (DB writes, external calls).
- State management: single source of truth; avoid mixing “cache truth” and “DB truth” without reconciliation.
- Invariants:
  - Never place/trigger the same action twice for the same logical entity.
  - Never transition state in an invalid order.
  - Always re-check critical preconditions close to execution if the world can change.

Failure modes:
- What happens if external dependencies fail or time out?
- Are retries safe (idempotent) and bounded (no infinite loops)?
- Are partial failures handled with clear compensation or persistence rules?

## Level 5 — Production Readiness Review (Safety)

Objective: make the change safe to ship.

Required checks:
- Observability: structured logs (or consistent log lines), including correlation/request IDs when available.
- External/API safety: timeouts, bounded retries with backoff, and verification of post-conditions.
- Graceful degradation: clear error propagation; avoid silent failures.
- Performance sanity: avoid accidental N+1, and keep work bounded (no unbounded loops).
- Testing coverage for the critical behavior:
  - at least one spec for the new behavior
  - edge cases for nil/boundaries
  - idempotency/duplicate prevention when side effects exist

Exit criteria:
- Level 2 + Level 4 must be green.
- Level 5 requires explicit safety and observability for any side-effecting changes.

## Output format (what to write back to the user)

For each finding, include:
- Level (1–5)
- File and symbol/method name (where possible)
- Why it fails or risks failure (one concise sentence)
- Concrete fix suggestion (smallest change that addresses it)


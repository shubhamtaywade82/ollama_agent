# OllamaAgent: Consolidated Feature Plan

Source: `docs/new_features.md` (26 iterative design rounds, ~11.7k lines).

## 0. Namespace Decision

Doc migrates `OllamaAgent::*` → `Ares::*` mid-document. **Override:** keep everything under `OllamaAgent::*`. New kernel lands in existing tree:

- `lib/ollama_agent/runtime/` — storage, mutator, saga, locks, manifest.
- `lib/ollama_agent/state/` — fingerprint, canonicalization, AST summarizer, re-entry packet, reconciler.
- `lib/ollama_agent/security/` — owners.yml compiler, ownership index, resource guard, criticality policy.
- `lib/ollama_agent/topology/` — symbol graph, IR, linker, extractors.
- `lib/ollama_agent/synthesis/` — integration extractor, route/sidekiq/event synthesizers.
- `lib/ollama_agent/llm/` — planner, context builder, supervisor, cloud fallback router, anthropic client.

Single gem, single namespace, no sibling library. Existing tool runtime delegates to new `OllamaAgent::Runtime::SagaCoordinator` when feature flag enabled.

## 1. Theme-by-Round Map

| Round | Lines | Theme | Key Components | Critical Invariants |
|---|---|---|---|---|
| 1 | 5 | Model selection (Kimi vs DeepSeek) | docs only | route reasoning vs context retrieval |
| 2 | 34 | Multi-provider matrix | docs only | local-first + cloud fallback |
| 3 | 72 | Failover gaps in current gem | `tool_runtime/cloud_fallback_router.rb`, supervisor interceptor, `<think>` stripper | runtime catches local failures, not the LLM |
| 4 | 435 | Execution boundary + state reconciliation | `tool_runtime/supervisor.rb`, `state/reconciler.rb` | LLM proposes, runtime executes/validates |
| 5 | 677 | Re-entry packet + token budgets | `state/context_builder.rb`, `state/reentry_packet.rb` | hard fail on budget overflow, no full-history replay |
| 6 | 1090 | AST summarizer + WAL + circuit breakers | `state/ast_summarizer.rb` (Prism), `tool_runtime/execution_journal.rb`, `MAX_ESCALATION_DEPTH=1` | semantic, not token, truncation |
| 7 | 1511 | SQLite WAL, semantic extractor, RBAC | `ollama_agent/state/semantic_extractor.rb`, `ollama_agent/runtime/wal.rb`, phase-scoped tool registry | O(1) idempotency, no stale workspace |
| 8 | 1983 | Path RBAC, composite fingerprint, intent_hash, event sourcing | `ollama_agent/state/workspace_fingerprint.rb`, `ollama_agent/security/resource_guard.rb` | mutation gated by realpath + intent |
| 9 | 2482 | Canonicalization, CAS, atomic transactions | `ollama_agent/runtime/canonicalization.rb`, `ollama_agent/runtime/atomic_mutator.rb` | deep-sort before hash; CAS pre-check |
| 10 | 2986 | Schema-aware canon, Saga pattern, post-conditions | schema registry, `SagaCoordinator`, `PostConditionVerifier` | sets vs sequences distinguished; planner emits validation |
| 11 | 3478 | POSIX rename, OverlayFS validator, reversibility tiers, snapshots | `IsolatedValidator` (Docker), reversibility tiers `{reversible, compensatable, irreversible}` | write-temp-fsync-rename; irreversibility halts auto-execution |
| 12 | 3999 | DB-native sequencing, OverlayFS specifics, cold WAL archival, lease-bound approvals, replay isolation | `ollama_agent/runtime/fencing_allocator.rb`, archival job, supervisor lease | AUTOINCREMENT only; replay stubs side effects |
| 13 | 4498 | Leased context locks + deadlock-free ordering + intent reservation | `ollama_agent/runtime/lock_manager.rb` | sorted lexical lock acquisition; pre-flight conflicts |
| 14 | 4930 | Fenced CAS + epoch TTLs + zero-trust intent + workspace DAG | fencing_token everywhere, epoch ints, parent_workspace_version | every mutation carries fencing_token |
| 15 | 5551 | **Phased roadmap (canonical 4-phase plan)** | — | bottom-up: storage → mutation → saga → LLM |
| 16 | 5842 | Split DBs, ExecutionMode global, exec manifests | `ollama_agent/runtime/database_registry.rb` (runtime.db + event_store.db), `ExecutionMode` (NORMAL/REPLAY/VALIDATION/DRY_RUN) | manifests are saga roots |
| 17 | 6416 | ExecutionContext (no globals), PRAGMA synchronous=FULL, lineage DAG, runtime fingerprinting | `ollama_agent/runtime/execution_context.rb`, ruby_patchlevel in fingerprint | mode bound to context, never global |
| 18 | 6881 | Explicit ownership graph (`config/ollama_agent/owners.yml`) | `ollama_agent/security/ownership_compiler.rb`, `OwnershipIndex`, mode-bound capabilities | boot-time topology validation |
| 19 | 7475 | Prefix-trie LPM ownership + path-traversal fix + privilege restriction + topology versioning + criticality | LPM index, owners.yml SHA in manifest | child mutable_in_modes ⊆ parent's |
| 20 | 7915 | Unified prefix engine + criticality policy matrix + state-gated saga | `ollama_agent/runtime/criticality_policy.rb` | critical → supervisor lease + no auto-compensation |
| 21 | 8523 | Reversibility ≠ integration; shell-injection prevention; saga checkpointing; immutable compensation | `MutationClassifier`, array-exec only, saga FSM | snapshot before CAS write |
| 22 | 9083 | Content-addressed blob store + strict FSM + validator path-guarded + runtime-derived integrations | `ollama_agent/runtime/blob_store.rb`, `IntegrationExtractor` | dedupe rollback storage; integrations derived, not planner-supplied |
| 23 | 9629 | Atomic+integrity-checked blobs, logical clocks, atomic compensations, exclusive recovery leases, manifest sealing | `ollama_agent/runtime/logical_clock.rb`, `SagaRecoveryDaemon` | no `Time.now` on orchestration path |
| 24 | 10243 | Symbol graph + incremental invalidation; "Compiler over Agent" | `ollama_agent/topology/symbol_graph.rb`, `Extractors::RubySemanticExtractor` | LLM emits intent only; runtime AST-derives integrations |
| 25 | 10772 | symbol_id stability; multi-origin aggregation; Zeitwerk parity; event-bus schema registry | `topology/symbol_identity.rb`, Zeitwerk inflector emulation | open classes aggregated |
| 26 | 11275 | Semantic signature normalization + staged/committed topology + 6-pass linker + Concern aggregation; need typed semantic IR | `topology/signature_normalizer.rb`, multi-pass linker, IR node classes | malformed code stays staged |

## 2. Epic List (Dependency-Ordered)

```text
E1  Storage Kernel               (Phase 1)
E2  Workspace Identity & Lineage (Phase 1)
E3  Ownership & Security         (Phase 2)
E4  Atomic Mutation (CAS)        (Phase 2)
E5  Locking & Intent Reservation (Phase 2.5)
E6  Saga Coordinator             (Phase 3)
E7  Isolated Validator           (Phase 3)
E8  Compensation & Recovery      (Phase 3)
E9  LLM Boundary                 (Phase 4)
E10 Cloud Escalation & Re-entry  (Phase 4)
E11 Topology Compiler            (Phase 5)
E12 Integration Synthesis        (Phase 5)
E13 Existing Runtime Integration (cross-cutting)
```

## 3. Per-Epic Detail

### E1. Storage Kernel

- **Components:** `OllamaAgent::Runtime::DatabaseRegistry`, `WAL`, `EventStore`, `FencingAllocator`, `Snapshots`, `IntegrationQueue`.
- **Files:**
  - `lib/ollama_agent/runtime/database_registry.rb` (split runtime.db / event_store.db, PRAGMA setup)
  - `lib/ollama_agent/runtime/wal.rb`
  - `lib/ollama_agent/runtime/event_store.rb`
  - `lib/ollama_agent/runtime/fencing_allocator.rb`
  - `lib/ollama_agent/runtime/integration_queue.rb`
  - `db/ollama_agent/schema.sql`
- **Acceptance:** PRAGMA `synchronous=FULL` on event store; AUTOINCREMENT yields gapless monotonic IDs under 1k concurrent inserts; replay of recorded WAL reproduces exact tree_hash.

### E2. Workspace Identity & Lineage

- **Components:** `Canonicalizer`, `WorkspaceFingerprint`, `ExecutionContext`, `ExecutionMode`, `LogicalClock`, `ExecutionManifest`.
- **Files:**
  - `lib/ollama_agent/runtime/canonicalization.rb` (schema-aware deep sort)
  - `lib/ollama_agent/state/workspace_fingerprint.rb` (sorted relpaths + Gemfile.lock + db/schema.rb + ruby_patchlevel + owners.yml SHA + critical ENV whitelist)
  - `lib/ollama_agent/runtime/execution_mode.rb`, `execution_context.rb`
  - `lib/ollama_agent/runtime/logical_clock.rb`
  - `lib/ollama_agent/runtime/execution_manifest.rb` (parent_manifest_id DAG)
- **Acceptance:** identical input directory → identical fingerprint across machines; replay rejects mismatched fingerprint with hard fault.

### E3. Ownership & Security (RBAC)

- **Components:** `OwnershipCompiler`, `OwnershipIndex` (LPM prefix trie), `ResourceGuard`, `CriticalityPolicy`.
- **Files:**
  - `config/ollama_agent/owners.yml`
  - `lib/ollama_agent/security/ownership_compiler.rb`
  - `lib/ollama_agent/security/ownership_index.rb`
  - `lib/ollama_agent/security/resource_guard.rb` (Pathname.realpath, prefix `+ File::SEPARATOR`)
  - `lib/ollama_agent/runtime/criticality_policy.rb`
- **Acceptance:** boot fails on overlapping prefixes / cycles / privilege-escalation in mutable_in_modes; `../` and symlink swaps rejected; `/repo2` does not match `/repo` prefix.

### E4. Atomic Mutation (CAS)

- **Components:** `AtomicMutator` (write-temp → fsync → inode-check → rename → fsync-parent), fenced CAS, intent_hash idempotency.
- **Files:**
  - `lib/ollama_agent/runtime/atomic_mutator.rb`
  - `lib/ollama_agent/runtime/cas_guard.rb` (expected_pre_hash + fencing_token + intent_hash)
- **Acceptance:** SIGKILL between write and rename leaves on-disk content unchanged; symlink swap during write raises `InodeSwapDetected`; replays reuse intent_hash to no-op duplicate writes.

### E5. Locking & Intent Reservation

- **Components:** `LockManager` (SQLite leased contexts, fenced, epoch TTLs), `IntentReservation`.
- **Files:**
  - `lib/ollama_agent/runtime/lock_manager.rb`
  - `lib/ollama_agent/runtime/intent_reservation.rb`
- **Acceptance:** lexicographically sorted acquisition order proven deadlock-free in 100-thread fuzz test; expired leases auto-purged; stale fencing tokens rejected by AtomicMutator.

### E6. Saga Coordinator

- **Components:** `SagaCoordinator` (FSM: RESERVED → LOCKED → MUTATIONS_APPLIED → VERIFIED → INTEGRATION_QUEUED → COMMITTED | COMPENSATED), `MutationClassifier`, lease-heartbeat checks at every transition, terminal manifest sealing.
- **Files:**
  - `lib/ollama_agent/runtime/saga_coordinator.rb`
  - `lib/ollama_agent/runtime/mutation_classifier.rb`
  - `lib/ollama_agent/runtime/saga_recovery_daemon.rb`
- **Acceptance:** kill -9 mid-saga → recovery daemon resumes/compensates exactly once; terminal manifests reject all subsequent writes.

### E7. Isolated Validator

- **Components:** `IsolatedValidator` (Docker run with `--cap-drop=ALL --network=none --read-only` + tmpfs overlay for `/tmp`, `/log`), array-exec only (no shell interpolation).
- **Files:**
  - `lib/ollama_agent/runtime/isolated_validator.rb`
  - `lib/ollama_agent/runtime/post_condition_verifier.rb`
  - `containers/ollama_agent-verification-sandbox.Dockerfile`
- **Acceptance:** validator image SHA256 captured in manifest; shell-injection attempts rejected; double-gated invariant evaluation (post-mutation and post-validation).

### E8. Compensation & Recovery

- **Components:** `BlobStore` (content-addressed, atomic, hash-verified on read), `CompensationManifest` (typed JSON `{exists: false}` sentinels), `CompensationEngine` (uses AtomicMutator), `SagaRecoveryDaemon` (transactional recovery lease).
- **Files:**
  - `lib/ollama_agent/runtime/blob_store.rb`
  - `lib/ollama_agent/runtime/compensation_manifest.rb`
  - `lib/ollama_agent/runtime/compensation_engine.rb`
- **Acceptance:** corrupted blob byte triggers `IntegrityFault`; rollback durable across power-fail; concurrent recovery daemons cannot double-compensate.

### E9. LLM Boundary

- **Components:** `Planner` (Qwen3 Coder / DeepSeek V3), `ContextBuilder` (10/30/50 budget), strict JSON schema coercion, `<think>` stripper, `Supervisor` (interceptor + retries + escalation triggers), phase-scoped tool registry.
- **Files:**
  - `lib/ollama_agent/llm/planner.rb`
  - `lib/ollama_agent/llm/context_builder.rb`
  - `lib/ollama_agent/llm/think_block_stripper.rb`
  - `lib/ollama_agent/tool_runtime/supervisor.rb`
  - `lib/ollama_agent/tool_runtime/tool_registry.rb` (phase-scoped capabilities)
- **Acceptance:** budget overflow raises hard error; invalid JSON triggers retry then escalation; tools unavailable in current phase rejected before LLM sees them.

### E10. Cloud Escalation & Re-entry

- **Components:** `CloudFallbackRouter` (direct Anthropic API client, not CLI), `Reconciler`, `ReentryPacket` builder, AST summarizer, circuit breakers (`MAX_ESCALATION_DEPTH=1`, cost cap, time cap).
- **Files:**
  - `lib/ollama_agent/llm/cloud_fallback_router.rb`
  - `lib/ollama_agent/llm/anthropic_client.rb`
  - `lib/ollama_agent/state/reconciler.rb`
  - `lib/ollama_agent/state/reentry_packet.rb`
  - `lib/ollama_agent/state/ast_summarizer.rb` (Prism, signature-only with touched_methods kept full)
- **Acceptance:** post-escalation fingerprint diff produces correct changed_files list; re-entry packet within token budget; second escalation in same saga refused.

### E11. Topology Compiler (Symbol Graph)

- **Components:** typed semantic IR (`ClassNode`, `ModuleNode`, `ConcernNode`, `EventPublisherNode`, `WorkerNode`, `RouteNode`, `CallbackNode`), `SymbolIdentity` (FQCN+signature+extractor_version hash), `SymbolGraph` (multi-origin aggregation), `SignatureNormalizer`, 6-pass linker (Discover → Resolve → Extract → Aggregate → Link → Validate), Zeitwerk inflector parity, staged-vs-committed promotion.
- **Files:**
  - `lib/ollama_agent/topology/ir/*.rb`
  - `lib/ollama_agent/topology/symbol_identity.rb`
  - `lib/ollama_agent/topology/symbol_graph.rb`
  - `lib/ollama_agent/topology/signature_normalizer.rb`
  - `lib/ollama_agent/topology/linker/{discovery,resolve,extract,aggregate,link,validate}.rb`
  - `lib/ollama_agent/topology/zeitwerk_inflector.rb`
  - `lib/ollama_agent/topology/extractors/ruby_semantic_extractor.rb` (Prism::Visitor)
- **Acceptance:** reordering methods does not change `signature_hash`; reopening a class across files produces one symbol_id with N origins; malformed code parks symbols in staged state without poisoning committed graph; mutating a file invalidates only its reverse-dependency closure.

### E12. Integration Synthesis

- **Components:** `IntegrationExtractor` (AST-derives routes, Sidekiq workers, AR topology, event publishers from certified state), `EventSchemaRegistry`, `IntegrationConflictResolver`. Build only after E11 fully linked + validated.
- **Files:**
  - `lib/ollama_agent/synthesis/integration_extractor.rb`
  - `lib/ollama_agent/synthesis/event_schema_registry.rb`
  - `lib/ollama_agent/synthesis/route_synthesizer.rb`
  - `lib/ollama_agent/synthesis/sidekiq_synthesizer.rb`
- **Acceptance:** synthesized routes/jobs match handwritten reference; event payload validation fails on unknown schema.

### E13. Existing Runtime Integration

- **Components:** route `OllamaAgent::Runner` turn-loop tool calls through `OllamaAgent::Runtime::SagaCoordinator` when `OLLAMA_AGENT_KERNEL=true`.
- **Files:**
  - `lib/ollama_agent/agent/turn_loop.rb` (modify to optionally route through kernel)
  - `lib/ollama_agent/tool_runtime.rb` (delegate atomic ops to AtomicMutator)
  - `lib/ollama_agent/external_agents.rb` (rewrite shell-out → direct Anthropic API client from E10)
- **Acceptance:** existing tests pass with kernel disabled; with kernel enabled, every file mutation appears in WAL and respects owners.yml.

## 4. Gaps vs Current Repo State

Current `lib/ollama_agent/` contains: `agent/`, `tool_runtime.rb`, `sandboxed_tools.rb`, `path_sandbox.rb`, `diff_path_validator.rb`, `patch_risk.rb`, `external_agents.rb`, `runner.rb`, `cli.rb`, `prompt_skills.rb`, `streaming/`, `context/`, `indexing/`, `ruby_index/`. The `feature/add-skills` branch carried v0.2.0 roadmap (Tool Registry + write_file, streaming hooks, retry middleware, audit logger, context manager, session persistence, Runner facade) — verify against branch state.

**Entirely missing:**

- No `runtime/`, `state/`, `security/`, `topology/`, `synthesis/`, `llm/` subtrees.
- No SQLite-backed WAL / event store / lock manager / fencing allocator.
- No CAS / atomic mutator / blob store / compensation engine.
- No Saga coordinator / FSM / recovery daemon.
- No owners.yml + ownership compiler + LPM index.
- No execution mode / context / manifest / logical clock.
- No isolated container validator.
- No symbol graph / typed IR / multi-pass linker / Zeitwerk parity.
- No cloud fallback router with direct Anthropic API client (`external_agents.rb` shells out).
- No Prism-based AST summarizer / semantic extractor.
- No re-entry packet builder.

**Reusable (with adapters):**

- `path_sandbox.rb`, `diff_path_validator.rb`, `patch_risk.rb` → inputs to `Security::ResourceGuard`.
- `context/manager.rb`, `context/token_counter.rb` → inputs to `LLM::ContextBuilder`.
- `streaming/hooks.rb` → bus for saga state-transition events.
- `ruby_index/` (Prism-aware) → seed for `topology/extractors`.
- `external_agents.rb` → reference for API-not-CLI cloud fallback rewrite.

## 5. Suggested Phasing into Milestones

**M1 — Storage Genesis (E1, E2)**
Acceptance: hand-authored JSON plan deterministically writes WAL entries, fingerprints workspace, replays exactly. No LLM.

**M2 — Mutation Boundary (E3, E4, E5)**
Acceptance: `OllamaAgent::Runtime.write!(intent)` blocks `.env`, requires lease, survives kill -9, idempotent on replay.

**M3 — Saga Lifecycle (E6, E7, E8)**
Acceptance: full Reserve → Lock → Mutate → Validate → Commit / Compensate cycle on a toy two-file change with rspec post-condition; SIGKILL at any state recovers cleanly.

**M4 — LLM Integration (E9, E10)**
Acceptance: Qwen3 plans single-step changes; on failure (3 retries) Anthropic API takes over once, returns Re-entry Packet, local planner resumes against post-state.

**M5 — Topology Compiler (E11)**
Acceptance: SymbolGraph builds from a representative Rails app, survives reopens, Concern includes, Zeitwerk auto-loads; mutation invalidates correct closure.

**M6 — Synthesis & Integration (E12, E13)**
Acceptance: IntegrationExtractor regenerates `config/routes.rb` from controllers; CLI flag `--kernel` (or `OLLAMA_AGENT_KERNEL=true`) routes all tool calls through new runtime with no observable regression.

**Branch strategy:** open `feature/runtime-kernel` from `main`. Do not block existing `feature/add-skills` merges. M1 and M2 are TDD-friendly and can land before any LLM coupling.

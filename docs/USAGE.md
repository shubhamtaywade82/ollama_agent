# ollama_agent usage guide

End-user workflows: install, configure, run the agent, optional kernel, cloud escalation, replay. CLI details live in `docs/CLI.md`; operations and incidents in `docs/OPERATIONS.md`.

---

## Installation

**From RubyGems** (when published):

```bash
gem install ollama_agent
```

**From a checkout:**

```bash
cd ollama_agent
bundle install
bundle exec ruby exe/ollama_agent help
```

**Requirements:**

- Ruby ≥ 3.2 (gemspec `required_ruby_version`).
- **sqlite3** gem (declared in gemspec); kernel mode creates `.ollama_agent/kernel/*.db`.
- **Ollama** reachable at `OLLAMA_HOST` (default `http://localhost:11434`) or provider keys for OpenAI/Anthropic.
- External tools: **`patch`** for `edit_file`; **`rg`** or **`grep`** for `search_code` text mode (see `README.md`).

**Optional Docker:** only for isolated validator flows (`docs/agile/docker_spec_activation.md`).

---

## First run

1. **Set workspace root** (the tree the agent may modify):

   ```bash
   export OLLAMA_AGENT_ROOT=/path/to/your/repo
   cd "$OLLAMA_AGENT_ROOT"
   ```

2. **Point at Ollama** (if not local default):

   ```bash
   export OLLAMA_HOST=http://localhost:11434
   ```

3. **Run a one-shot task:**

   ```bash
   bundle exec ollama_agent ask "List top-level files and summarize README"
   ```

4. **Named session** (transcript under `.ollama_agent/sessions/` — see `lib/ollama_agent/session/store.rb`):

   ```bash
   bundle exec ollama_agent ask --session demo1 "Plan a small refactor"
   bundle exec ollama_agent ask --session demo1 --resume "Continue the plan"
   ```

5. **List sessions:**

   ```bash
   bundle exec ollama_agent sessions
   ```

---

## Tool calling primer

- The **model** proposes tool calls; **`OllamaAgent::Agent`** (`lib/ollama_agent/agent.rb`) executes them via **`SandboxedTools`** (`lib/ollama_agent/sandboxed_tools.rb`) inside the **workspace root**.
- **Read-only mode:** `--read-only` / `-R` removes write/patch/delegation tools from the schema (`lib/ollama_agent/tools_schema.rb`).
- **Confirmation:** patch application can require user confirmation unless `-y` or patch policy auto-approves (`lib/ollama_agent/sandboxed_tools.rb`, `PatchRisk`).
- **Safety:** paths outside root are rejected (`lib/ollama_agent/path_sandbox.rb`). Treat `OLLAMA_AGENT_ROOT` as the trust boundary.

**`search_code`:** `mode` defaults to text (ripgrep/grep). Modes `class`, `module`, `constant`, `method` use the **Prism-backed Ruby index** (`lib/ollama_agent/ruby_index/`).

---

## Skill system

**Prompt skills (markdown):** bundled skills and `OLLAMA_AGENT_SKILL_PATHS` / `--skill-paths`; toggled with `--no-skills` or `OLLAMA_AGENT_SKILLS=0`. Wired through `PromptSkills` / agent prompt (`lib/ollama_agent/prompt_skills.rb`).

**Deterministic JSON skills (CLI):**

```bash
ollama_agent skill list
ollama_agent skill run architecture_refactor --code-file lib/foo.rb
```

See `lib/ollama_agent/cli/skill_command.rb` and `lib/ollama_agent/skills/` for contracts.

---

## Kernel mode tutorial

**When to use:** you need **auditable** mutations (WAL + sagas), **ownership** rules, optional **shadow** rehearsal, and operator **health** / **schema migrations** / **cost ledger** integration.

**Enable:**

```bash
export OLLAMA_AGENT_KERNEL=true   # or shadow — see README
bundle exec ollama_agent ask "Edit lib/foo.rb to add a comment"
```

**Behavior summary:** `lib/ollama_agent/runtime/kernel_bridge.rb` routes configured tools through `KernelPipeline` when `KernelFeature.enabled?` (`lib/ollama_agent/runtime/kernel_feature.rb`).

### `owners.yml` walkthrough

Ship **`config/ollama_agent/owners.yml`** at repo root (or workspace-relative path consumed by `KernelPipelineAssembly` — see `lib/ollama_agent/runtime/kernel_pipeline_assembly.rb`).

**Example** (excerpt from `config/ollama_agent/owners.yml` in this repository):

```yaml
version: 1
rules:
  - prefix: app
    owner: application
    mutable_in_modes: [normal, replay, validation, dry_run]
    criticality: routine
    forbidden: false
    children:
      - prefix: app/models
        owner: domain
        mutable_in_modes: [normal, replay, validation]
        criticality: sensitive
        children: []

  - prefix: .env
    owner: secrets
    mutable_in_modes: [normal, replay, validation, dry_run]
    criticality: critical
    forbidden: true
    children: []
```

**`forbidden: true`:** mutations under that prefix are denied by ownership (use for `.env`, secrets dirs).

**Compile:** `OllamaAgent::Security::OwnershipCompiler` / index consumed by pipeline and `PermissionBridge` (`lib/ollama_agent/runtime/permission_bridge.rb`).

**Health before relying on kernel:**

```bash
bundle exec ollama_agent kernel health --root "$OLLAMA_AGENT_ROOT"
echo "exit=$?"
```

---

## Cloud escalation setup

Used when integrating **`CloudFallbackRouter`** (`lib/ollama_agent/llm/cloud_fallback_router.rb`) with **`AnthropicClient`** (`lib/ollama_agent/llm/anthropic_client.rb`).

**Environment:**

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

**Breakers (defaults in router):** `max_escalation_depth`, `cost_cap_usd`, `time_cap_seconds` — see initializer on `CloudFallbackRouter`. With **`cost_ledger:`**, cumulative cost per manifest is read from **`runtime.db`** table `cost_ledger` (see `lib/ollama_agent/runtime/cost_ledger.rb`).

**Escalation triggers:** application code calls `escalate` when local model or validator path fails; this gem does not auto-escalate every `ask` unless you wire it in your integration.

---

## Workspace etiquette

- **Root:** only paths under `OLLAMA_AGENT_ROOT` (or agent `root:`) participate in tools.
- **Secrets:** mark paths **`forbidden: true`** in `owners.yml` (example: `.env`).
- **Kernel SQLite and blobs:** `.ollama_agent/kernel/` contains `event_store.db`, `runtime.db`, `blobs/`, optional `event_store_archive.db`. Add to backup/ignore policies as appropriate.

---

## Replay and debugging

**Global WAL replay onto a copy of a tree:**

```ruby
require "ollama_agent"
OllamaAgent::Runtime::WorkspaceWalReplay.new(
  workspace_root: "/tmp/replay-tree",
  event_store_db_path: "/path/to/.ollama_agent/kernel/event_store.db",
  blob_store_kernel_dir: "/path/to/.ollama_agent/kernel"
).replay!
```

Source: `lib/ollama_agent/runtime/workspace_wal_replay.rb`. Use a **copy** of the workspace; replay overwrites files according to WAL.

**Event inspection:**

```bash
sqlite3 .ollama_agent/kernel/event_store.db "SELECT id, manifest_id, kind FROM events ORDER BY id DESC LIMIT 20;"
```

---

## Shadow mode walkthrough

```bash
export OLLAMA_AGENT_KERNEL=shadow
bundle exec ollama_agent ask "Perform a write that would normally hit AtomicMutator"
```

**Expect:** saga + WAL + hooks run; workspace bytes for configured shadow operations are **not** committed like production `true` mode (see `docs/agile/release_rollout_runbook.md` and `ExecutionMode` in `lib/ollama_agent/runtime/execution_mode.rb`). Compare WAL payloads and saga transitions in `runtime.db` against expectations before flipping to `true`.

---

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| `SQLite3::Exception` on first kernel use | disk permissions or corrupt db | Fix permissions; move aside `.ollama_agent/kernel` and retry (data loss risk—snapshot first). |
| Health `degraded` / schema | migration lag | Run `kernel health`; inspect `schema_migrations` tables in both DBs (`docs/OPERATIONS.md`). |
| `Permission denied` tools | `Permissions` profile or ownership | Kernel on: check `owners.yml` + `PermissionBridge` logs; kernel off: `--permissions` / env. |
| Empty model / connection errors | `OLLAMA_HOST` / model name | `ollama_agent agents` unrelated; verify Ollama tags and `OLLAMA_AGENT_MODEL`. |
| Anthropic `429` / timeouts | rate limits / network | Client retries (`lib/ollama_agent/llm/anthropic_client.rb`); tune `open_timeout_seconds` / `request_timeout_seconds`. |

---

## Further reading

- `README.md` — overview and security.
- `docs/CLI.md` — all subcommands.
- `docs/CAPABILITIES.md` — matrix of features.
- `docs/OPERATIONS.md` — incidents, SQL, compaction.

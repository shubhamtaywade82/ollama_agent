# ollama_agent CLI reference

Entry point: `exe/ollama_agent` → `OllamaAgent::CLI` (`lib/ollama_agent/cli.rb`). **Thor** is used; `CLI.exit_on_failure?` is **true**, so uncaught errors typically yield **exit code 1**.

**Default task:** `ask`. Invoking `ollama_agent` with no subcommand runs `ask` (same as `ollama_agent ask`).

**Global behavior:** many commands call `load_plugins!` (see `Plugins::Loader`) when applicable.

**Root resolution:** most commands use `OLLAMA_AGENT_ROOT` or `--root`, else current working directory (see `resolved_root_for_self_review` in `lib/ollama_agent/cli.rb`).

---

## `ask [QUERY]` (default)

**Syntax:** `ollama_agent [options] [QUERY]` or `ollama_agent ask [options] [QUERY]`

**Description:** Run one task with a query string, or enter **interactive** mode when `QUERY` is empty (TUI vs line REPL depends on `--interactive` / `--tui`; see `apply_session_interactive_tui_flags!`).

**Common options** (from `lib/ollama_agent/cli.rb`):

| Option | Alias | Meaning |
|--------|-------|---------|
| `--model` | | Model id (default from `OLLAMA_AGENT_MODEL` / client) |
| `--interactive` | `-i` | Interactive session |
| `--tui` | | TTY UI when interactive |
| `--tui-god` | | Auto-pick first TUI choice (dangerous) |
| `--read-only` | `-R` | No write/patch/delegation tools |
| `--yes` | `-y` | Skip patch confirmation |
| `--root` | | Project root |
| `--timeout` | `-t` | HTTP timeout seconds (default 120) |
| `--think` | | Thinking / reasoning level (model-specific) |
| `--no-skills` | | Disable bundled skills (`OLLAMA_AGENT_SKILLS=0` equivalent) |
| `--skill-paths` | | Colon-separated extra skill paths |
| `--stream` | | Stream tokens (`OLLAMA_AGENT_STREAM=1` equivalent) |
| `--audit` | | Audit log under `.ollama_agent/logs/` |
| `--max-retries` | | HTTP retries (0 disables) |
| `--session` | | Named session id |
| `--resume` | | Resume session |
| `--max-tokens` | | Context budget |
| `--context-summarize` | | Summarize dropped context |
| `--provider` | | `ollama` (default) \| `openai` \| `anthropic` \| `auto` |
| `--permissions` | | `read_only` \| `standard` \| `developer` \| `full` |
| `--trace` | | Structured trace (`OLLAMA_AGENT_TRACE=1`) |

**Examples:**

```bash
bundle exec ollama_agent ask "Summarize lib/ for a newcomer"
bundle exec ollama_agent ask --read-only -R "List risks only"
bundle exec ollama_agent ask -y --root /path/to/repo "Apply the patch plan"
bundle exec ollama_agent ask --session myfeat --resume "Continue where we left off"
```

**Exit codes:** `0` on success; `1` on agent/CLI errors (`run_single_shot_agent!` rescues and `exit 1`).

---

## `orchestrate [QUERY]`

**Syntax:** `ollama_agent orchestrate [options] [QUERY]`

Same interactive / TUI flags as `ask` where declared. Builds an agent with **orchestrator** enabled (`build_orchestrator_agent`). Adds delegation tools (`list_external_agents`, `delegate_to_agent`) per `README.md`.

**Examples:**

```bash
bundle exec ollama_agent orchestrate "Delegate a subtask to claude if stuck"
```

**Exit codes:** same pattern as `ask`.

---

## `sessions`

**Syntax:** `ollama_agent sessions [--root PATH]`

Lists saved session ids for the resolved root (`Session::Store.list`).

**Exit codes:** `0`.

---

## `agents` and `doctor`

**Syntax:** `ollama_agent agents` — `ollama_agent doctor` is an **alias** for `agents`.

Prints external CLI agent registry probe table (`ExternalAgents::Registry`, `ExternalAgents::Probe`).

**Exit codes:** `0`.

---

## `self_review`

**Syntax:** `ollama_agent self_review [options]`

**Modes** (`--mode`, normalized in `SelfImprovement::Modes`):

- `analysis` (default, aliases `1`, `readonly`) — read-only tools, report.
- `interactive` (`2`, `fix`, `confirm`) — full tools, confirm patches (`--yes` / `--semi`).
- `automated` (`3`, `sandbox`, `full`) — sandbox copy, agent, `bundle exec rspec`, optional `--apply`.

**Notable options:** `--root`, `--timeout`, `--think`, `--yes`, `--semi`, `--apply` (automated), `--verify` (automated), `--no-skills`, `--skill-paths`, `--stream`, `--max-tokens`, `--context-summarize`, `--no-ruby-mastery`.

**Examples:**

```bash
bundle exec ollama_agent self_review --mode analysis
bundle exec ollama_agent self_review --mode interactive --root .
bundle exec ollama_agent self_review --mode automated --apply --yes
```

**Exit codes:** `1` if improve/verify fails (see `report_improve_result`); `0` on success paths.

---

## `improve`

**Syntax:** `ollama_agent improve [options]`

Shortcut for **`self_review --mode automated`**. Rejects non-automated modes (`ensure_improve_mode_only_automated!`).

**Exit codes:** same as automated self_review.

---

## `skill` (subcommand)

Defined in `lib/ollama_agent/cli/skill_command.rb`, mounted as `CLI.subcommand "skill", CLI::SkillCommand`.

### `skill list`

**Syntax:** `ollama_agent skill list`

Prints registered skill names (`Skills.registry.names`).

**Exit codes:** `0`.

### `skill run NAME`

**Syntax:** `ollama_agent skill run NAME [--code-file PATH] [--requirements TEXT] [--error TEXT] [--model MODEL]`

Runs one skill; prints **JSON** (`JSON.pretty_generate`).

**Exit codes:** `0` on success; Thor raises on missing file / errors (→ process exit `1` with `exit_on_failure?`).

**Example:**

```bash
ollama_agent skill run architecture_refactor --code-file lib/foo.rb
```

### `skill pipeline NAME [NAME ...]`

**Syntax:** `ollama_agent skill pipeline SKILL [SKILL ...] [same options as run]`

Runs a deterministic pipeline of skills.

**Example:**

```bash
ollama_agent skill pipeline architecture_refactor performance_optimizer --code-file lib/foo.rb
```

---

## `kernel` (subcommand)

Defined in `lib/ollama_agent/cli/health_command.rb` as `CLI::KernelHealthCommand`, mounted `CLI.subcommand "kernel", ...`.

### `kernel health`

**Syntax:** `ollama_agent kernel health [--root PATH]`

Opens kernel SQLite under `<root>/.ollama_agent/kernel/`, runs `KernelHealth#check`, prints **one JSON object** to stdout.

**Exit codes:**

- `0` if top-level `"status"` is `"ok"`.
- `1` if `"degraded"` or `"unhealthy"` (or any non-ok status).

**Example:**

```bash
bundle exec ollama_agent kernel health --root /path/to/repo
```

Interpretation of `checks` keys: see `docs/OPERATIONS.md`.

---

## Thor / invocation notes

- **Subcommand spelling:** use spaces (`ollama_agent kernel health`), not a colon.
- **Default executable:** after `gem install`, `ollama_agent` on `PATH`; from source often `bundle exec ruby exe/ollama_agent …`.
- **Help:** `ollama_agent help`, `ollama_agent help ask`, `ollama_agent help skill`, `ollama_agent help kernel`.

---

## Quick reference table

| Command | Purpose |
|---------|---------|
| `ask` / (no subcommand) | Main agent |
| `orchestrate` | Agent + external CLI delegation |
| `sessions` | List sessions |
| `agents`, `doctor` | External agent probe |
| `self_review` | Analysis / interactive / automated improvement |
| `improve` | Automated self_review only |
| `skill list\|run\|pipeline` | Deterministic JSON skills |
| `kernel health` | Kernel DB + blob + schema readiness JSON |

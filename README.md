# ollama_agent

Version: 1.0.0

Ruby gem that runs a **CLI coding agent** against a local [Ollama](https://ollama.com) model. It exposes tools to **list files**, **read files**, **search the tree** (ripgrep or grep), and **apply unified diffs** so the model can make small, reviewable edits.

## Features

- Tool `list_files` – list project files.
- Tool `read_file` – read file contents.
- Tool `search_code` – search code with ripgrep or grep.
- Tool `edit_file` – apply unified diffs safely.
- CLI built with Thor, entry point `exe/ollama_agent`.
- **`self_review`** – self-review / improvement with a **`--mode`**:
  - **`analysis`** (default, alias `1`) — read-only tools; report only; no writes.
  - **`interactive`** (alias `2`, `fix`) — full tools on `--root`; you confirm each patch (like `ask`); optional `-y` / `--semi`.
  - **`automated`** (alias `3`, `sandbox`) — temp copy, agent edits, **`bundle exec rspec`** in the sandbox, optional **`--apply`** to merge into your checkout.
- **`improve`** — same as **`self_review --mode automated`** (you can pass **`--mode automated`** explicitly; other modes belong on **`self_review`**).
- **`orchestrate`** / **`OLLAMA_AGENT_ORCHESTRATOR=1`** — optional **orchestrator** tools to probe and delegate to other local CLI agents (see [Orchestrator](#orchestrator-external-cli-agents)); **`agents`** lists availability.
- **Ruby API** — embed **`Runner`**, **`Agent`**, custom tools, hooks, sessions, and (optionally) **`ToolRuntime`**; see [Library usage (Ruby)](#library-usage-ruby).

## Requirements

- Ruby ≥ 3.2 (enforced in the gemspec as `required_ruby_version`)
- **Local:** Ollama running and a capable tool-calling model, **or**
- **Ollama Cloud:** API key and a cloud-capable model name (see below)

### Prerequisites (external tools)

- **`patch`** — required for `edit_file` (GNU `patch` on `PATH`). On Windows, use Git Bash, WSL, GnuWin32, or another environment that provides `patch`.
- **`rg` (ripgrep) or `grep`** — text mode for `search_code` needs at least one of these on `PATH` (ripgrep is preferred when present).

## Installation

From RubyGems (when published) or from this repository:

```bash
bundle install
```

## Usage

**Default:** run the gem with **no subcommand** to open the **interactive TUI** (same as `ask` with no query):

```bash
ollama_agent
# or from this repo:
bundle exec ruby exe/ollama_agent
```

Other entry points are **opt-in**: pass a **subcommand** (`self_review`, `sessions`, …) or **`ask` / `orchestrate`** with a **query** for a one-shot task, or flags for a plain line REPL (see below).

From the project you want the agent to modify (set the working directory accordingly):

```bash
bundle exec ruby exe/ollama_agent ask "Update the README.md with current codebase"
```

From this repository after `bundle install`, `ruby exe/ollama_agent` (without `bundle exec`) also works: the executable adds `lib` to the load path and loads `bundler/setup` when a `Gemfile` is present.

Apply proposed patches without interactive confirmation:

```bash
bundle exec ruby exe/ollama_agent ask -y "Your task"

# Review / audit only (no patches, writes, or delegation)—same as a report-style self_review
bundle exec ruby exe/ollama_agent ask --read-only "Summarize risks in this repo"
```

Long-running models (slow local inference):

```bash
bundle exec ruby exe/ollama_agent ask --timeout 300 "Your task"
```

### Agent budget (steps, tokens, cost)

Each **model round-trip** that runs during a session counts as one **step** toward `OLLAMA_AGENT_MAX_TURNS` (default **64**), enforced together with token and optional cost limits in `OllamaAgent::Core::Budget`. Exploratory tasks that **list, read, and search** across a **large repository** can burn through steps quickly; if you see `budget exceeded — step limit (64)`, raise the limit—for example:

```bash
export OLLAMA_AGENT_MAX_TURNS=128
bundle exec ruby exe/ollama_agent ask "Your wide-ranging task"
```

Narrower prompts, **`--read-only`**, or a smaller `--root` also reduce step usage. With **`OLLAMA_AGENT_DEBUG=1`**, the agent prints an extra hint when the **maximum tool rounds** for a run are reached.

### `search_code` and regex patterns

In **text** mode, the tool passes your pattern to **ripgrep** (or **grep**). Patterns are **regular expressions**: literal parentheses, brackets, and unbalanced groups can trigger errors (for example `unclosed group`). Escape metacharacters or use **fixed-string** mode when your tool schema exposes it.

**Plain line REPL** (no TUI boxes / markdown shell): use **`ask` (or `orchestrate`) with `-i` and without `--tui`**—for example when you omit the query you must opt out of the default TUI this way:

```bash
bundle exec ruby exe/ollama_agent ask --interactive
# same idea: explicit -i, no --tui
```

Self-review modes (default project root is the **current working directory** unless you set `--root` or `OLLAMA_AGENT_ROOT`):

```bash
# Mode 1 — analysis only (default)
bundle exec ruby exe/ollama_agent self_review
bundle exec ruby exe/ollama_agent self_review --mode analysis

# Mode 2 — optional fixes in the working tree (confirm each patch, or -y / --semi)
bundle exec ruby exe/ollama_agent self_review --mode interactive

# Mode 3 — sandbox + tests + optional merge back (same as `improve`)
# Without --apply, edits stay in a temp dir only; pass --apply to copy changed files into your checkout.
bundle exec ruby exe/ollama_agent self_review --mode automated
bundle exec ruby exe/ollama_agent self_review --mode automated --apply
bundle exec ruby exe/ollama_agent improve --apply
```

**`ruby_mastery` (optional):** When the [`ruby_mastery`](https://github.com/shubhamtaywade82/ruby_mastery) gem is installed (this repo lists it in the `Gemfile` for development), **`self_review`** (all modes) and **`improve`** prepend a **markdown static-analysis** section to the user prompt. Add the same gem to your app’s `Gemfile` if you want that behavior outside this checkout. Disable with **`--no-ruby-mastery`** or **`OLLAMA_AGENT_RUBY_MASTERY=0`**. Limit size with **`OLLAMA_AGENT_RUBY_MASTERY_MAX_CHARS`** (default `60000`).

For mode 3, `-y` skips all patch prompts; `--no-semi` prompts for every patch when not using `-y`.

With a **thinking-capable** model, enable reasoning output:

```bash
OLLAMA_AGENT_THINK=true bundle exec ruby exe/ollama_agent ask -i
# or
bundle exec ruby exe/ollama_agent ask -i --think true
```

The CLI uses **ANSI colors** on a TTY (banner, prompt, patch prompts). **Assistant replies** are rendered as **Markdown** (headings, lists, bold, code fences) via `tty-markdown` when stdout is a TTY and **`NO_COLOR`** is unset. Disable Markdown rendering with **`OLLAMA_AGENT_MARKDOWN=0`**. Disable all colors with **`NO_COLOR`** or **`OLLAMA_AGENT_COLOR=0`**.

When **thinking** is enabled, internal reasoning is shown under a **Thinking** label; the user-facing reply is labeled **Assistant** in green when the model returns both fields. By default (**`OLLAMA_AGENT_THINKING_STYLE=compact`**, Cursor-like), one **Thinking** header is printed per `ask` run and every later reasoning chunk in that run is appended with **blank lines only** (no repeated banner, no rule lines)—including after turns where the model printed tool JSON or other non-empty `content`. Set **`OLLAMA_AGENT_THINKING_STYLE=framed`** for the legacy boxed style (banner + long rulers on every assistant message). Thinking body text is **plain dim** by default. Set **`OLLAMA_AGENT_THINKING_MARKDOWN=1`** to render thinking through Markdown too (muted colors).

With **`--stream`** / **`OLLAMA_AGENT_STREAM=1`**, reasoning streams in **dim** text under a single **Thinking** line, then **`Assistant`** and the reply stream in normal styling—closer to Cursor than printing everything as one token stream. (This uses a small hook on ollama-client’s chat stream; `hooks[:on_thinking]` is also emitted for custom subscribers.)

### Ollama Cloud

[Ollama Cloud](https://docs.ollama.com/cloud) uses the same HTTP API as the local server, with HTTPS and a Bearer API key. The **ollama-client** gem sends `Authorization: Bearer <api_key>` when `Ollama::Config#api_key` is set (HTTPS is used when the URL scheme is `https`).

1. Create a key at [ollama.com/settings/keys](https://ollama.com/settings/keys).
2. Point the agent at the cloud host and pass the key (same env names as ollama-client’s docs):

```bash
export OLLAMA_BASE_URL="https://ollama.com"
export OLLAMA_API_KEY="your_key"
export OLLAMA_AGENT_MODEL="gpt-oss:120b-cloud"   # example; pick a cloud model from `ollama list` / the catalog
bundle exec ruby exe/ollama_agent ask "Your task"
```

### Environment

| Variable | Purpose |
|----------|---------|
| `OLLAMA_BASE_URL` | Ollama API base URL (default from ollama-client: `http://localhost:11434`; use `https://ollama.com` for cloud) |
| `OLLAMA_API_KEY` | API key for Ollama Cloud (`https://ollama.com`); optional for local HTTP |
| `OLLAMA_AGENT_MODEL` | Model name (overrides default from ollama-client) |
| `OLLAMA_AGENT_ROOT` | Project root for tools (`list_files`, `read_file`, etc.). Defaults to **current working directory** when unset (CLI never falls back to the gem install path). |
| `OLLAMA_AGENT_DEBUG` | Set to `1` to print validation diagnostics on stderr |
| `OLLAMA_AGENT_STRICT_ENV` | Set to `1` so invalid numeric env values (e.g. `OLLAMA_AGENT_MAX_TURNS`) raise `ConfigurationError` instead of falling back to defaults |
| `OLLAMA_AGENT_MAX_TURNS` | Max chat rounds with tool calls (default: 64) |
| `OLLAMA_AGENT_TIMEOUT` | HTTP read/open timeout in seconds for Ollama requests (default **120**; use `ask --timeout` / `-t` to override per run) |
| `OLLAMA_AGENT_PARSE_TOOL_JSON` | Set to `1` to run tools parsed from JSON lines in assistant text (fallback when the model does not emit native tool calls) |
| `NO_COLOR` | Set (any value) to disable ANSI colors (see [no-color.org](https://no-color.org/)) |
| `OLLAMA_AGENT_COLOR` | Set to `0` to disable colors even on a TTY |
| `OLLAMA_AGENT_MARKDOWN` | Set to `0` to disable Markdown formatting of assistant replies (plain text only) |
| `OLLAMA_AGENT_THINKING_STYLE` | `compact` (default) = one **Thinking** label per run, blank lines between later reasoning chunks; `framed` = repeat full banner/rulers each message |
| `OLLAMA_AGENT_THINKING_MARKDOWN` | Set to `1` to render **thinking** text with Markdown (muted); default is plain dim text |
| `OLLAMA_AGENT_THINK` | Model **thinking** mode for compatible models: `true` / `false`, or `high` / `medium` / `low` (see ollama-client `think:`). Empty = omit (server default). |
| `OLLAMA_AGENT_PATCH_RISK_MAX_DIFF_LINES` | Max changed-line count before a diff is treated as "large" for semi-auto patch risk (default **80**) |
| `OLLAMA_AGENT_INDEX_REBUILD` | Set to `1` to drop the cached Prism Ruby index before the next symbol search in this process |
| `OLLAMA_AGENT_RUBY_INDEX_MAX_FILES` | Max `.rb` files to parse per index build (default **5000**) |
| `OLLAMA_AGENT_RUBY_INDEX_MAX_FILE_BYTES` | Skip Ruby files larger than this many bytes (default **512000**) |
| `OLLAMA_AGENT_RUBY_INDEX_MAX_LINES` | Max result lines for `search_code` class/module/method modes (default **200**) |
| `OLLAMA_AGENT_RUBY_INDEX_MAX_CHARS` | Max characters of index output per search (default **60000**) |
| `OLLAMA_AGENT_MAX_READ_FILE_BYTES` | Max bytes for a **full** `read_file` (no line range); larger files return an error (default **2097152**, 2 MiB). Line-range reads stream and are not limited by this cap. |
| `OLLAMA_AGENT_RG_PATH` | Absolute path to `rg` for `search_code` text mode (optional; otherwise first `rg` on `PATH`) |
| `OLLAMA_AGENT_GREP_PATH` | Absolute path to `grep` fallback (optional; otherwise first `grep` on `PATH`) |
| `OLLAMA_AGENT_INDEX_REBUILD` | The Prism index is rebuilt when this env value **changes** (e.g. unset → `1`); it is **not** rebuilt on every tool call while it stays `1`. |
| `OLLAMA_AGENT_SKILLS` | `1`/`on`/`0`/`off` — include **bundled** prompt skills (default **on**). Same as `--no-skills` on the CLI when off. |
| `OLLAMA_AGENT_SKILLS_INCLUDE` | Comma-separated **manifest ids** to load (omit = all bundled). Example: `ruby_style,rubocop,code_review`. |
| `OLLAMA_AGENT_SKILLS_EXCLUDE` | Comma-separated ids to skip from the bundled set. |
| `OLLAMA_AGENT_SKILL_PATHS` | Extra `.md` files or directories, **colon-separated** (Unix `PATH` style). Directory entries load all `*.md` in sorted order. Merged with `--skill-paths`. |
| `OLLAMA_AGENT_EXTERNAL_SKILLS` | `1`/`0` — include content from `OLLAMA_AGENT_SKILL_PATHS` (default **on**). Set `0` to use bundled-only without unsetting paths. |

### Prompt skills (bundled + optional paths)

The system prompt is the **base agent instructions** (`AgentPrompt`) plus optional **Markdown** sections. Bundled files live under `lib/ollama_agent/prompt_skills/` and are listed in `manifest.yml`. Each file may use Cursor-style YAML frontmatter (`---` … `---`); the loader strips frontmatter before sending text to the model.

**Manifest ids** (in load order): `clean_ruby`, `ruby_style`, `rubocop`, `solid`, `solid_ruby`, `design_patterns`, `rspec`, `rails_style`, `rails_best_practices`, `code_review`, `ollama_agent_patterns`.

Bundled bodies were copied from Cursor `SKILL.md` files under `~/.cursor/skills/` (and `ollama_agent_patterns` from this repo’s `.cursor/skills/ollama-agent-patterns`). Re-copy when you update those skills upstream.

Many full skills can be **large**; use `OLLAMA_AGENT_SKILLS_INCLUDE` to trim for small-context models.

CLI flags (also available on `ask`, `self_review`, `improve`): `--no-skills`, `--skill-paths 'path1:path2/dir'`.

To run **`self_review` / `ask` against the installed gem’s source** (e.g. to hack on `ollama_agent` itself), pass an explicit root, for example `--root "$(bundle show ollama_agent)"` or a path to a git clone.

### Orchestrator (external CLI agents)

Use the **`orchestrate`** command (or **`OLLAMA_AGENT_ORCHESTRATOR=1`** with **`ask`**) to expose tools **`list_external_agents`** and **`delegate_to_agent`**. The Ollama model should gather context with **`read_file` / `search_code`**, list installed CLIs, then delegate a **short** task + context to an external agent (Claude Code, Gemini CLI, Codex, Cursor CLI, etc.). Definitions live in `lib/ollama_agent/external_agents/default_agents.yml`; override or extend via **`~/.config/ollama_agent/agents.yml`** or **`OLLAMA_AGENT_EXTERNAL_AGENTS_CONFIG`**.

- **`ollama_agent agents`** — print a table of configured agents and whether each binary is on `PATH`.
- **`ollama_agent doctor`** — alias for `agents`.
- **`delegate_to_agent`** runs a **fixed argv** (no shell) with **`cwd`** = project root; output is capped (**`OLLAMA_AGENT_DELEGATE_MAX_OUTPUT_BYTES`**, default 100k). Confirm each run unless **`-y`**.
- Delegation audit logs: set **`OLLAMA_AGENT_DELEGATE_LOG=1`** (or `OLLAMA_AGENT_DEBUG=1`) to emit a structured stderr line with agent id, argv, env keys (names only), exit code, and duration.
- Adjust **`argv` / `version_argv`** in YAML to match your real CLI (vendor flags differ). If a tool has no stable non-interactive mode, do not expose it in the registry.
- Tool contract version: **`OllamaAgent::ORCHESTRATOR_TOOLS_SCHEMA_VERSION`**.

### Library usage (Ruby)

Most of this README is **CLI-first** (commands and environment variables above). The same capabilities exist as **Ruby APIs**—the [Features](#features) list (file tools, `self_review` / `improve`, orchestrator, skills, etc.) is implemented under `lib/ollama_agent/`. For a **layer diagram** (agent → tools → hooks → session), see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

**Coding agent — `Runner` (facade)** — Stable entry for apps: `OllamaAgent::Runner.build(root:, model:, stream:, session_id:, resume:, read_only:, orchestrator:, skills_enabled:, skill_paths:, audit:, max_tokens:, context_summarize:, stdin:, stdout:, ...)` then `#run(query)`. Optional **`stdin`** / **`stdout`** (default TTY) feed patch/write/delegate confirmations—use `StringIO` in tests or automation to avoid blocking on `$stdin.gets`. Exposes `#hooks` (`Streaming::Hooks`) for `:on_token`, `:on_thinking` (streamed reasoning when `stream: true` and the model supports it), `:on_tool_call`, `:on_tool_result`, `:on_complete`. Full keyword list: [`lib/ollama_agent/runner.rb`](lib/ollama_agent/runner.rb).

**Coding agent — `Agent` (direct)** — `OllamaAgent::Agent.new(client:, root:, ...)` when you inject an `Ollama::Client` (or test double), tweak options the CLI does not expose, or skip `Runner`.

**Custom tools (coding agent)** — `OllamaAgent::Tools.register("tool_name", schema: { ... }) { |args, root:, read_only:| ... }` merges extra function definitions into the chat tool list; handlers run in the same sandbox as built-in tools.

**Resilience and observability** — Default client path uses `Resilience::RetryMiddleware`. Structured step logging: enable **`audit: true`** on `Runner.build` or **`OLLAMA_AGENT_AUDIT=1`** (see Environment table). Context trimming: **`max_tokens`** / **`context_summarize`** on `Runner.build`.

**Sessions** — Pass **`session_id`** and optional **`resume: true`** on `Runner.build` to persist messages under `.ollama_agent/sessions/` (`Session::Store`).

**Self-improvement (sandbox)** — CLI commands **`improve`** / **`self_review --mode automated`** wrap `OllamaAgent::SelfImprovement` (sandbox copy, tests, optional merge). Use the CLI for the full flow; the module is available for advanced integration.

**`ToolRuntime` (alternate loop, optional)** — Not used by the CLI. For **non–file-edit** agents (e.g. another gem that defines its own tools), a small **JSON plan** loop: the model returns one object per step `{"tool":"name","args":{...}}`, `ToolRuntime::Registry` resolves it, `Executor` runs your `Tool` subclasses, `Memory` holds short-term history. Use a **swappable planner** (anything implementing `next_step(context:, memory:, registry:)`) such as `OllamaJsonPlanner` (`Ollama::Client#chat` + JSON extraction). **Step-by-step guide:** [docs/TOOL_RUNTIME.md](docs/TOOL_RUNTIME.md).

- **Termination:** a tool may return `{ "status" => "done" }` to stop. Unknown tool names → `OllamaAgent::ToolRuntime::InvalidPlanError`; too many steps → `MaxStepsExceeded`. **`Loop#run`** returns the **last tool result** (same value as the final `Executor#execute` return).
- **Runnable examples:** `spec/ollama_agent/tool_runtime/`.

**Model and server:** `OllamaJsonPlanner` uses the same default as the coding agent: `OLLAMA_AGENT_MODEL` if set, otherwise `Ollama::Config.new.model` (from ollama-client). The model must exist on whatever host you use. **Use the same client setup as the CLI:** `OllamaAgent::OllamaConnection.apply_env_to_config` copies `OLLAMA_BASE_URL` and `OLLAMA_API_KEY` into `Ollama::Config`. If you only run `Ollama::Client.new(config: Ollama::Config.new)` in `irb`, you stay on **localhost** while `OLLAMA_AGENT_MODEL` may still name a **cloud** model from the README cloud example → **404**. Either apply `apply_env_to_config` (below) or unset the cloud model / pass `model: "llama3.2"`.

```ruby
require "ollama_agent"
require "ollama_client"

class EchoTool < OllamaAgent::ToolRuntime::Tool
  def name = "echo"

  def description = "Echo args"

  def schema = { "type" => "object", "properties" => { "msg" => { "type" => "string" } } }

  def call(args)
    return { "status" => "done", "echo" => args["msg"] } if args["msg"] == "bye"

    { "status" => "ok", "echo" => args["msg"] }
  end
end

registry = OllamaAgent::ToolRuntime::Registry.new([EchoTool.new])
memory = OllamaAgent::ToolRuntime::Memory.new
config = Ollama::Config.new
OllamaAgent::OllamaConnection.apply_env_to_config(config)
client = Ollama::Client.new(config: config)
planner = OllamaAgent::ToolRuntime::OllamaJsonPlanner.new(client: client)

last = OllamaAgent::ToolRuntime::Loop.new(
  planner: planner,
  registry: registry,
  executor: OllamaAgent::ToolRuntime::Executor.new,
  memory: memory,
  max_steps: 10
).run(context: "Say hello then echo bye to finish.")
# last => e.g. { "status" => "done", "echo" => "bye" }
```

## Troubleshooting

- **Use a tool-capable model** — Set `OLLAMA_AGENT_MODEL` to a model that supports function/tool calling (e.g. a recent coder-tuned variant). If the model only prints `{"name": "read_file", ...}` in plain text, tools never run unless you enable `OLLAMA_AGENT_PARSE_TOOL_JSON=1`.
- **Malformed diffs** — Headers must look like `git diff`: `--- a/file` then `+++ b/file` then a unified hunk line starting with `@@` (not legacy `--- N,M ----`). Do not put commas after path tokens. The gem normalizes some mistakes and runs `patch --dry-run` before applying.
- **Request timeouts** — The agent defaults to a **120s** HTTP timeout (longer than ollama-client’s 30s). If you still hit `Ollama::TimeoutError`, raise it with `OLLAMA_AGENT_TIMEOUT=300`, `bundle exec ruby exe/ollama_agent ask --timeout 300 "..."`, or `-t 300`. Ensure the variable name is exactly `OLLAMA_AGENT_TIMEOUT` (a leading typo such as `vOLLAMA_AGENT_TIMEOUT` is ignored).

## How it works

1. The CLI starts `OllamaAgent::Agent`, which loops on `Ollama::Client#chat` with tool definitions.
2. Tools are executed in-process under a **path sandbox** (`OLLAMA_AGENT_ROOT`).
3. **`search_code`** defaults to **ripgrep/grep** (`mode` omitted or `text`). For Ruby, use `mode` **`method`**, **`class`**, **`module`**, or **`constant`** to query a **Prism** parse index (built lazily on first use). **`read_file`** accepts optional **`start_line`** / **`end_line`** (1-based, inclusive) to read only part of a file.
4. Patches are validated and checked with **`patch --dry-run`** before you confirm (unless `-y`).

## Development

```bash
bundle exec rspec
bundle exec rubocop
```

### CI and RubyGems release

- **CI** — [`.github/workflows/main.yml`](.github/workflows/main.yml) runs **RSpec** and **RuboCop** on pushes to `main` / `master` and on pull requests (Ruby **3.3.4** and **3.2.0**).
- **Release** — [`.github/workflows/release.yml`](.github/workflows/release.yml) runs on tags `v*`. It checks that the tag matches `OllamaAgent::VERSION` in [`lib/ollama_agent/version.rb`](lib/ollama_agent/version.rb), builds with `gem build ollama_agent.gemspec`, and pushes to RubyGems.

Repository **secrets** (Settings → Secrets and variables → Actions):

| Secret | Purpose |
|--------|---------|
| `RUBYGEMS_API_KEY` | RubyGems API key with **push** scope |
| `RUBYGEMS_OTP_SECRET` | Base32 secret for **TOTP** (RubyGems MFA); the workflow uses `rotp` to generate a one-time code for `gem push` |

Release steps:

1. Bump `OllamaAgent::VERSION` in `lib/ollama_agent/version.rb` and commit to `main`.
2. Tag: `git tag v1.0.0` (must match the version string) and `git push origin v1.0.0`.

## License

MIT. See [LICENSE.txt](LICENSE.txt).

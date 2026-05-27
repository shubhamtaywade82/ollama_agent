# OllamaAgent — Complete Feature Reference

Version **1.0.0** · Ruby ≥ 3.2

This document is the single authoritative reference for every feature of the gem.
For deeper treatment of individual subsystems see the companion docs:
[ARCHITECTURE.md](ARCHITECTURE.md) · [TOOLS.md](TOOLS.md) · [SESSIONS.md](SESSIONS.md) · [TOOL_RUNTIME.md](TOOL_RUNTIME.md)

---

## Contents

1. [CLI Commands](#1-cli-commands)
2. [Agent and Runner API](#2-agent-and-runner-api)
3. [Built-in Tools](#3-built-in-tools)
4. [Enhanced Tools](#4-enhanced-tools)
5. [Custom Tool Registration](#5-custom-tool-registration)
6. [Tool Base Class](#6-tool-base-class)
7. [Permission Profiles](#7-permission-profiles)
8. [Approval Gate](#8-approval-gate)
9. [Session Management](#9-session-management)
10. [Memory System](#10-memory-system)
11. [Streaming and Hooks](#11-streaming-and-hooks)
12. [Resilience](#12-resilience)
13. [Context Management](#13-context-management)
14. [Provider Abstraction](#14-provider-abstraction)
15. [Ruby Indexing (Prism)](#15-ruby-indexing-prism)
16. [ToolRuntime (Alternate Loop)](#16-toolruntime-alternate-loop)
17. [Skills System](#17-skills-system)
18. [Self-Improvement](#18-self-improvement)
19. [Orchestrator and External Agents](#19-orchestrator-and-external-agents)
20. [Plugin System](#20-plugin-system)
21. [Core Kernel](#21-core-kernel)
22. [Sandbox Isolation](#22-sandbox-isolation)
23. [Environment Variables](#23-environment-variables)

---

## 1. CLI Commands

Entry point: `exe/ollama_agent` (or `bundle exec ruby exe/ollama_agent`).
Default task when no subcommand is given: **`ask`** with the interactive TUI.

### `ask [QUERY]`

Run a task against the local model. Omit `QUERY` to open the interactive TUI.

```bash
ollama_agent ask "Refactor the auth module"
ollama_agent ask -i                          # plain line REPL (no TUI)
ollama_agent                                  # interactive TUI (default)
```

| Flag | Short | Description |
|------|-------|-------------|
| `--model` | | Ollama model name |
| `--interactive` | `-i` | Without `--tui`: plain line REPL |
| `--tui` | | Force TUI even with a query |
| `--tui-god` | | Auto-select first option in TUI lists (dangerous) |
| `--read-only` | `-R` | Disable edit_file, write_file, patches |
| `--yes` | `-y` | Apply patches without confirmation |
| `--root` | | Project root (default: `OLLAMA_AGENT_ROOT` or cwd) |
| `--timeout` | `-t` | HTTP timeout in seconds (default: 120) |
| `--think` | | Thinking mode: `true`, `false`, `high`, `medium`, `low` |
| `--stream` | | Stream tokens to stdout |
| `--no-skills` | | Disable bundled prompt skills |
| `--skill-paths` | | Extra `.md` files/dirs, colon-separated |
| `--audit` | | Write structured audit log |
| `--max-retries` | | HTTP retry attempts (default: 3; 0 to disable) |
| `--session` | | Named session id (saves/resumes conversation) |
| `--resume` | | Resume the named or most-recent session |
| `--max-tokens` | | Context window budget |
| `--context-summarize` | | Summarize dropped context (vs sliding window) |
| `--provider` | | `ollama` (default) \| `openai` \| `anthropic` \| `auto` |
| `--permissions` | | `read_only` \| `standard` (default) \| `developer` \| `full` |
| `--trace` | | Enable structured trace logging |

---

### `orchestrate [QUERY]`

Like `ask`, plus exposes `list_external_agents` and `delegate_to_agent` tools so the
model can hand off sub-tasks to other local CLI agents (Claude Code, Gemini CLI, etc.).

Same flags as `ask`. `--yes`/`-y` also skips delegation confirmations.
Equivalent to `ask --orchestrator` / `OLLAMA_AGENT_ORCHESTRATOR=1`.

---

### `self_review`

Run the agent over the current project in one of three modes.

```bash
ollama_agent self_review                       # analysis (default)
ollama_agent self_review --mode interactive    # confirm each patch
ollama_agent self_review --mode automated      # sandbox + tests + optional merge
```

| Mode | Aliases | Behavior |
|------|---------|----------|
| `analysis` | `1`, `readonly`, `read-only` | Read-only; report only; no writes |
| `interactive` | `2`, `fix`, `confirm` | Full tools; you confirm each patch |
| `automated` | `3`, `sandbox`, `full` | Temp copy of project; runs tests; `--apply` merges back |

Additional flags beyond `ask`: `--mode`, `--semi` (auto-confirm low-risk patches in interactive), `--apply` (merge sandbox back to source), `--verify` (comma-separated: `syntax`, `rubocop`, `rspec`), `--no-ruby-mastery`.

---

### `improve`

Shortcut for `self_review --mode automated`. Accepts all the same flags.

```bash
ollama_agent improve --apply
```

---

### `sessions`

List saved sessions for the current project root (newest first).

```bash
ollama_agent sessions
ollama_agent sessions --root /path/to/project
```

---

### `agents` / `doctor`

Print a table of all configured external CLI agents with availability status
(whether the binary is on `PATH`).

```bash
ollama_agent agents
ollama_agent doctor   # alias
```

---

### `skill list|run|pipeline`

Work with deterministic JSON-contract skill pipelines.

```bash
ollama_agent skill list
ollama_agent skill run architecture_refactor --code-file lib/orders.rb
ollama_agent skill pipeline architecture_refactor performance_optimizer \
  --code-file lib/orders.rb
```

Override the model with `--model`, `OLLAMA_AGENT_SKILL_MODEL`, or `OLLAMA_AGENT_MODEL`.

---

## 2. Agent and Runner API

### Runner (stable public facade)

`OllamaAgent::Runner` is the recommended entry point for library consumers.
Its interface is under SemVer contract from 1.0.0.

```ruby
runner = OllamaAgent::Runner.build(
  root:               Dir.pwd,     # project root
  model:              nil,         # OLLAMA_AGENT_MODEL or ollama-client default
  stream:             false,
  session_id:         nil,
  resume:             false,
  read_only:          false,
  orchestrator:       false,
  skills_enabled:     true,
  skill_paths:        [],
  confirm_patches:    true,
  think:              nil,         # true/false/"high"/"medium"/"low"
  http_timeout:       120,
  max_retries:        3,
  audit:              false,
  max_tokens:         32_768,
  context_summarize:  false,
  provider:           nil,         # Providers::Base instance
  permissions:        nil,         # Runtime::Permissions instance
  budget:             nil,         # Core::Budget instance
  trace:              false,
  stdin:              $stdin,
  stdout:             $stdout
)

result = runner.run("Your task here")

# Attach event listeners before calling #run:
runner.hooks.on(:on_tool_call)   { |p| puts "calling #{p[:name]}" }
runner.hooks.on(:on_tool_result) { |p| puts "result: #{p[:result]}" }
runner.hooks.on(:on_complete)    { |p| puts "done in #{p[:turns]} turns" }

runner.session_id  # => String | nil
```

### Agent (direct)

Use `OllamaAgent::Agent` when you inject your own `Ollama::Client` or need options
that `Runner` does not expose.

```ruby
require "ollama_client"
require "ollama_agent"

client = Ollama::Client.new(config: Ollama::Config.new)
agent  = OllamaAgent::Agent.new(
  client:          client,
  root:            "/my/project",
  model:           "gemma4:e2b",
  read_only:       false,
  confirm_patches: false,    # skip interactive confirmation
  think:           "medium"
)

agent.run("Add RSpec tests for the billing module")
agent.assign_chat_model!("llama3.2")   # switch model mid-session
agent.list_local_model_names           # => ["gemma4:e2b", "llama3.2", ...]
agent.list_cloud_model_names           # => [...] from ollama.com catalog
agent.hooks                            # => Streaming::Hooks
```

**Constants**

| Constant | Value | Purpose |
|----------|-------|---------|
| `MAX_TURNS` | 64 | Default step limit per `run` |
| `DEFAULT_HTTP_TIMEOUT` | 120 | Seconds before HTTP timeout |

**Convenience shortcut**

```ruby
OllamaAgent.run("task", root: "/my/project")
# Equivalent to Runner.build(root: ...).run("task")
```

---

## 3. Built-in Tools

All tools below are available in every permission profile unless noted.
They are exposed automatically in the Ollama tool schema via `CORE_TOOLS`.

### Tool reference

| Tool name | Module | Risk | Approval | Description |
|-----------|--------|------|----------|-------------|
| `read_file` | SandboxedTools | low | no | Read file with optional line slice |
| `search_code` | SandboxedTools | low | no | Search with ripgrep or Prism Ruby index |
| `list_files` | SandboxedTools | low | no | List paths under a directory |
| `edit_file` | SandboxedTools | low | configurable | Apply a unified diff |
| `write_file` | SandboxedTools | low | configurable | Create or overwrite a file |
| `list_directory_contents` | FilesystemExplorer | low | no | Sandboxed directory listing |
| `calculate` | SafeCalculator | low | no | Shunting-yard arithmetic (no eval) |

### `read_file`

```
path        String  required  File path relative to project root
start_line  Integer optional  First line to read (1-based, inclusive)
end_line    Integer optional  Last line to read (1-based); omit = EOF
```

Limit: `OLLAMA_AGENT_MAX_READ_FILE_BYTES` (default 2 MiB) for full reads.
Line-range reads stream and are not limited by that cap.

### `search_code`

```
pattern    String  required  Regex or symbol name
directory  String  optional  Subdirectory to search (default: project root)
mode       String  optional  text (default) | class | module | constant | method
```

- **`text`** mode: ripgrep (preferred) or grep fallback.
- **`class`/`module`/`constant`/`method`** modes: Prism Ruby AST index (no grep).

Limits: `OLLAMA_AGENT_RUBY_INDEX_MAX_LINES` (200), `OLLAMA_AGENT_RUBY_INDEX_MAX_CHARS` (60 000).

### `list_files`

```
directory   String  optional  Directory to scan (default: .)
max_entries Integer optional  Cap on results (default 100, max 500)
max_depth   Integer optional  Path depth limit (omit = unlimited; 1 = immediate children)
```

Skips `.git` and other VCS directories.

### `edit_file`

```
path  String  required  File path relative to project root
diff  String  required  Unified diff (git format)
```

Diff format: `--- a/<path>`, `+++ b/<path>`, `@@ hunk @@`, lines prefixed with space/`-`/`+`.
Validation pipeline: path check → `patch --dry-run` → forbidden-pattern check → optional user confirmation.

### `write_file`

```
path     String  required  File path relative to project root
content  String  required  Full UTF-8 file content
```

Prefer `edit_file` for surgical changes. `write_file` is for new files or complete rewrites.

### `list_directory_contents`

```
path  String  optional  Relative path inside workspace (default: .)
```

Returns `[DIR]  name/` and `[FILE] name (N bytes)` lines.
Rejects path traversal (`../../etc`, `/etc`, any path escaping the workspace root)
before the filesystem is touched — the check is a prefix comparison on the resolved
absolute path, not a regex.

### `calculate`

```
expression  String  required  Arithmetic expression
```

Operators: `+`, `-`, `*`, `/`, `**` (power, right-associative), unary `+`/`-`, parentheses.
`2 ** 3 ** 2` → `512.0`. Division by zero → non-finite error string. No `eval`.

---

## 4. Enhanced Tools

These tools inherit from `Tools::Base` and ship with the gem but are **not**
included in the default tool schema sent to the model. Register them via the
plugin system or custom tool registration when you want to expose them.

### Shell: `run_shell`

```ruby
OllamaAgent::Tools::RunShell.new(
  allowlist:      [...],   # Array<Regexp>; must match at least one
  denylist:       [...],   # Array<Regexp>; always blocked
  timeout:        30,      # seconds (max 120)
  dry_run:        false,
  redact_secrets: true
)
```

```
command         String  required  Shell command
working_dir     String  optional  Relative to project root
timeout_seconds Integer optional  Override timeout (max 120)
```

**Risk: high — requires approval.**

Default allowlist commands: `git`, `bundle`, `rspec`, `rubocop`, `ruby`, `echo`,
`printf`, `cat`, `ls`, `pwd`, `mkdir`, `cp`, `mv`, `awk`, `sed`, `grep`, `find`,
`yarn`, `npm`, `make`.

Default denylist patterns: `rm -rf`, `sudo`, `chmod 777`, fork bombs,
`curl|bash`, `wget|bash`, writes to `/etc` or `/usr`, `dd of=/dev/*`,
`mkfs`, `passwd`, `visudo`, `crontab -r/-e`.

Secret redaction from output: passwords, API tokens, AWS keys, JWTs.
Max output: 64 KB per stream.

### Git tools

| Class | Tool name | Risk | Approval | Parameters |
|-------|-----------|------|----------|------------|
| `GitStatus` | `git_status` | low | no | `short` (boolean) |
| `GitDiff` | `git_diff` | low | no | `ref` (default HEAD), `cached` (boolean), `path` |
| `GitLog` | `git_log` | low | no | `n` (1-100, default 10), `oneline`, `author`, `path` |
| `GitCommit` | `git_commit` | medium | yes | `message` (required, min 3 chars), `files` (array), `all` (boolean) |
| `GitBranch` | `git_branch` | low | no | `all` (boolean), `current` (boolean) |

`GitDiff` truncates output at 32 KB with a `[truncated]` note.

### HTTP tools

| Class | Tool name | Risk | Approval | Notes |
|-------|-----------|------|----------|-------|
| `HttpGet` | `http_get` | medium | no | GET request |
| `HttpPost` | `http_post` | high | yes | JSON POST |

`HttpGet` parameters:

```
url       String  required  Full URL (http:// or https://)
headers   Object  optional  Key-value HTTP headers
max_bytes Integer optional  Truncate at N bytes (default 32768, max 131072)
```

`HttpGet` safety controls:
- Allowed schemes: `http`, `https`
- Allowed content types: text/plain, text/html, text/markdown, application/json, application/xml, text/xml, text/csv, application/yaml, text/yaml
- **Blocks private/internal addresses**: 127.x, 10.x, 172.16-31.x, 192.168.x, `localhost`, `::1`, `0.0.0.0`, `*.local`
- Optional host allowlist and denylist

`HttpPost` strips dangerous request headers (Authorization, Cookie, Set-Cookie).

### Memory tools

| Class | Tool name | Risk | Parameters |
|-------|-----------|------|------------|
| `MemoryStore` | `memory_store` | low | `key` (req), `value` (req), `namespace` (default: `"default"`) |
| `MemoryRecall` | `memory_recall` | low | `key` (req), `namespace` |
| `MemoryList` | `memory_list` | low | `namespace` |
| `MemoryDelete` | `memory_delete` | medium | `key` (req), `namespace` |

Memory tools delegate to the **Memory Manager**'s long-term tier (see §10).

---

## 5. Custom Tool Registration

Register a custom tool before creating a `Runner` or `Agent`. The definition is
merged automatically into the Ollama tool schema.

```ruby
OllamaAgent::Tools.register(
  "run_tests",
  schema: {
    description: "Run the RSpec suite and return output",
    properties: {
      suite: { type: "string", description: "Path to spec file or dir (default: spec/)" }
    },
    required: []
  }
) do |args, root:, read_only:|
  return "disabled in read-only mode" if read_only

  require "open3"
  out, = Open3.capture2("bundle", "exec", "rspec", args["suite"] || "spec/", chdir: root)
  out
end

runner = OllamaAgent::Runner.build(root: Dir.pwd)
runner.run("Fix the failing tests, then run them to confirm they pass")
```

**Handler signature**: `|args, root:, read_only:| → String`

**Registry API**

```ruby
OllamaAgent::Tools.custom_tool?(name)                    # → Boolean
OllamaAgent::Tools.execute_custom(name, args, root:, read_only:)
OllamaAgent::Tools.custom_schemas                        # → Array of schema hashes
OllamaAgent::Tools.reset!                                # Clear all registrations
```

---

## 6. Tool Base Class

Subclass `OllamaAgent::Tools::Base` to define a fully-typed, permissioned,
auditable tool. Instances can be added to the agent via the plugin system.

```ruby
class MyTool < OllamaAgent::Tools::Base
  tool_name        "my_tool"
  tool_description "Does something useful"
  tool_risk        :low        # :low | :medium | :high | :critical
  tool_requires_approval false # default: true when risk is :high or :critical
  tool_schema({
    type: "object",
    properties: {
      input: { type: "string", description: "Value to process" }
    },
    required: ["input"]
  })

  def call(args, context: {})
    root      = context[:root]       # project root String
    read_only = context[:read_only]  # Boolean
    memory    = context[:memory_manager]
    args["input"].upcase
  end
end
```

**Schema output**

```ruby
tool = MyTool.new
tool.to_ollama_schema     # { type: "function", function: { name:, description:, parameters: } }
tool.to_anthropic_schema  # { name:, description:, input_schema: }
```

---

## 7. Permission Profiles

Passed as `--permissions` CLI flag or `permissions:` on `Runner.build`.

| Profile | Allowed tools | Denied tools |
|---------|---------------|--------------|
| `read_only` | read_file, list_files, search_code, git_status, git_log, git_diff, memory_recall, memory_list, http_get, list_directory_contents, calculate | — |
| `standard` *(default)* | Above + edit_file, write_file, memory_store, memory_delete | run_shell, git_commit, http_post |
| `developer` | Above + git_commit, git_branch, run_shell | http_post |
| `full` | All tools | — |

**Custom profile**

```ruby
perms = OllamaAgent::Runtime::Permissions.new(
  profile: :standard,
  allowed: %w[read_file search_code my_custom_tool],  # override profile allowlist
  denied:  %w[write_file]                              # always applied on top
)
runner = OllamaAgent::Runner.build(permissions: perms)
```

**API**

```ruby
perms.allowed?("edit_file")         # → Boolean
perms.filter_schemas(tool_schemas)  # → Array (only allowed tools)
perms.profile                       # → :standard
perms.to_h
```

---

## 8. Approval Gate

`OllamaAgent::Runtime::ApprovalGate` governs whether a high-risk tool call
proceeds automatically or requires user confirmation.

```ruby
gate = OllamaAgent::Runtime::ApprovalGate.new(
  auto_approve:   false,
  risk_threshold: :medium,           # auto-approve everything below :medium
  tool_overrides: { "run_shell" => false, "git_commit" => true },
  stdin:          $stdin,
  stdout:         $stdout
)
```

**Risk levels**: `:low` < `:medium` < `:high` < `:critical`

**Decision precedence**

1. `auto_approve: true` → approve everything
2. `tool_overrides[name]` → per-tool override (true/false)
3. `risk_threshold` → auto-approve if tool risk < threshold
4. Tool's `requires_approval` flag
5. Default: prompt user interactively

```ruby
gate.approved?("run_shell", args: {}, risk_level: :high, approval_required: true)
gate.last_decision  # → { tool: "run_shell", approved: false }
```

---

## 9. Session Management

Sessions persist the full conversation history under `<root>/.ollama_agent/sessions/`.

**CLI**

```bash
ollama_agent ask --session my-refactor "Continue where we left off"
ollama_agent ask --session my-refactor --resume "Keep going"
ollama_agent sessions              # list all saved sessions (newest first)
```

**Ruby API**

```ruby
# Save a message
OllamaAgent::Session::Store.save(
  session_id: "my-refactor",
  root:       "/my/project",
  message:    { role: "user", content: "..." }
)

# Load history
messages = OllamaAgent::Session::Store.load(
  session_id: "my-refactor",
  root:       "/my/project"
)

# List sessions for a project
OllamaAgent::Session::Store.list("/my/project")
# => [#<SessionMeta session_id="my-refactor" started_at="2026-05-27T10:00:00Z">]
```

**Persistence**

- Directory: `<project_root>/.ollama_agent/sessions/`
- Format: NDJSON — one JSON message object per line (crash-safe append)
- Filename: `<sanitized_session_id>.ndjson` (non-alphanumeric → `_`)

---

## 10. Memory System

Three independent tiers; all accessible through `Memory::Manager`.

```ruby
memory = OllamaAgent::Memory::Manager.new(
  root:           "/my/project",
  session_id:     "my-session",     # required for session tier
  long_term_path: nil               # default: ~/.config/ollama_agent/memory/
)
```

### Short-term memory

Ephemeral; cleared at the end of each run. Holds tool-call traces and
observations for the current conversation turn.

```ruby
memory.record_tool_call("read_file", { path: "lib/foo.rb" }, result)
memory.record_observation("Found 3 failing tests")
memory.recent_context(n = 10)   # → Array of recent entries
```

### Session memory

Key-value store scoped to the current session. Persisted in YAML at
`<root>/.ollama_agent/sessions/<session_id>.memory.yml`.

```ruby
memory.set("goal", "Refactor auth module")
memory.get("goal")                # → "Refactor auth module"
memory.all                        # → Hash
memory.delete("goal")
memory.set_goal("Fix login bug")
memory.complete_goal("Fix login bug")
memory.active_goals               # → Array<String>
```

### Long-term memory

Global persistent store under `~/.config/ollama_agent/memory/` (one YAML
file per namespace). Shared across all projects and sessions.

```ruby
memory.remember("db_schema", schema_text, namespace: "project_x")
memory.recall("db_schema",              namespace: "project_x")
memory.forget("db_schema",              namespace: "project_x")
memory.list(tier: :long_term, namespace: "project_x")
memory.search("schema",                 namespace: "project_x")
```

### Manager summary

```ruby
memory.summary
# => { short_term_entries: 12, session_keys: ["goal"], long_term_namespaces: ["default", "project_x"] }
memory.flush_short_term!
```

---

## 11. Streaming and Hooks

`OllamaAgent::Streaming::Hooks` is an event bus attached to every `Agent`/`Runner`
instance. Handlers can be registered before calling `#run`.

### Events

| Event | Payload keys | Fired when |
|-------|-------------|------------|
| `on_token` | `token:` | A text token arrives (streaming mode) |
| `on_thinking` | `token:` | A reasoning token arrives (thinking models) |
| `on_chunk` | `text:` | A larger assembled text chunk |
| `on_tool_call` | `name:`, `args:`, `turn:`, `call_id:` | The model calls a tool |
| `on_tool_result` | `name:`, `result:`, `turn:`, `latency_ms:`, `call_id:` | Tool returns a result |
| `on_assistant_message` | `message:`, `turn:` | Full assistant message assembled |
| `on_complete` | `messages:`, `turns:`, `budget:` | Run finishes |
| `on_error` | `error:`, `turn:` | An error occurs |
| `on_retry` | `error:`, `attempt:`, `delay_ms:` | HTTP retry triggered |

### Usage

```ruby
runner = OllamaAgent::Runner.build(root: Dir.pwd, stream: true, think: true)

runner.hooks.on(:on_thinking)    { |p| print p[:token] }
runner.hooks.on(:on_token)       { |p| print p[:token] }
runner.hooks.on(:on_tool_call)   { |p| puts "\n→ #{p[:name]}(#{p[:args]})" }
runner.hooks.on(:on_tool_result) { |p| puts "  ← #{p[:result][0, 120]}" }
runner.hooks.on(:on_complete)    { |p| puts "\nDone in #{p[:turns]} turns" }

runner.run("Explain the session store implementation")
```

Handler exceptions are silently swallowed so a bad subscriber never crashes a run.

```ruby
hooks.subscribed?(:on_token)  # → Boolean
hooks.emit(:on_token, { token: "x" })
```

---

## 12. Resilience

### Retry Middleware

`OllamaAgent::Resilience::RetryMiddleware` wraps `Ollama::Client` with
exponential backoff. Applied automatically when using `Runner`.

```ruby
OllamaAgent::Resilience::RetryMiddleware.new(
  client:       ollama_client,
  max_attempts: 4,    # ENV OLLAMA_AGENT_MAX_RETRIES
  base_delay:   1.0,  # ENV OLLAMA_AGENT_RETRY_BASE_DELAY (seconds)
  hooks:        hooks
)
```

**Retryable conditions**: `ConnectionError`, `TimeoutError`, HTTP 429, 502, 503, 504.
**Not retried**: 4xx errors other than 429, authentication failures.
**Backoff**: `base_delay × 2^(attempt − 1)` seconds.
Emits `on_retry` hook on each attempt.

### Audit Logger

`OllamaAgent::Resilience::AuditLogger` subscribes to hooks and writes
structured NDJSON to `<root>/.ollama_agent/logs/<YYYY-MM-DD>.ndjson`.

```ruby
OllamaAgent::Resilience::AuditLogger.new(
  log_dir:          ".ollama_agent/logs",
  hooks:            runner.hooks,
  max_result_bytes: 4096          # ENV OLLAMA_AGENT_AUDIT_MAX_RESULT_BYTES
)
```

Logged events: `tool_call`, `tool_result`, `agent_complete`, `agent_error`, `http_retry`.
Enable via `--audit` / `OLLAMA_AGENT_AUDIT=1`.

---

## 13. Context Management

`OllamaAgent::Context::Manager` trims the message list before each chat call
so it stays within the token budget.

```ruby
OllamaAgent::Context::Manager.new(
  max_tokens:        32_768,   # ENV OLLAMA_AGENT_MAX_TOKENS
  context_summarize: false     # true: inject summary of dropped messages
)
```

**Trimming strategy**

1. Never remove the system message or the last user message.
2. Start trimming at 85% of `max_tokens`.
3. Drop the oldest user/assistant/tool messages first.
4. Collapse `assistant + tool_results` pairs when removing pairs.
5. When `context_summarize: true`, inject a short summary of the dropped history.

**Token counting**: uses `tiktoken_ruby` if available (GPT-4 tokenizer);
falls back to `characters / 4` otherwise.

---

## 14. Provider Abstraction

Three built-in providers; extendable via the plugin system.

### Providers

| Provider | Class | Env key | Notes |
|----------|-------|---------|-------|
| `ollama` *(default)* | `Providers::Ollama` | `OLLAMA_BASE_URL` | Local or cloud; supports streaming and thinking |
| `openai` | `Providers::OpenAI` | `OPENAI_API_KEY` | GPT-4o, GPT-4-turbo, GPT-3.5, etc. |
| `anthropic` | `Providers::Anthropic` | `ANTHROPIC_API_KEY` | Claude 3.x; extended thinking on claude-3-7-sonnet |

### Selection

```bash
ollama_agent ask --provider openai "Refactor this module"
ollama_agent ask --provider auto   "..."   # picks first available
```

`auto` tries: Ollama → OpenAI (if `OPENAI_API_KEY` set) → Anthropic (if `ANTHROPIC_API_KEY` set).

### Router (fallback chain)

```ruby
router = OllamaAgent::Providers::Registry.router(
  ["ollama", "openai"],
  strategy: :first_available
)
# Emits on_provider_fallback hook when switching
```

### Provider API (implementing a custom provider)

```ruby
class MyProvider < OllamaAgent::Providers::Base
  def initialize(name:, **opts); end
  def chat(messages:, model:, tools: nil, stream_hooks: nil, **opts) = ...  # → Response
  def available?             = true
  def streaming_supported?   = false
  def estimate_cost(input_tokens:, output_tokens:) = 0.0
end

OllamaAgent::Providers::Registry.register("my_provider", MyProvider)
```

**Response fields**: `message.role`, `message.content`, `message.tool_calls`,
`usage.prompt_tokens`, `usage.completion_tokens`, `usage.total_tokens`.

---

## 15. Ruby Indexing (Prism)

When `search_code` is called with `mode:` set to `class`, `module`, `constant`,
or `method`, the gem builds a Prism AST index of all `.rb` files under the
project root and returns matching definitions — no grep required.

**Index is built lazily** on first use and cached in-process.
Force rebuild: `OLLAMA_AGENT_INDEX_REBUILD=1` (change triggers rebuild).

**Limits**

| Variable | Default | Purpose |
|----------|---------|---------|
| `OLLAMA_AGENT_RUBY_INDEX_MAX_FILES` | 5 000 | Max `.rb` files per index build |
| `OLLAMA_AGENT_RUBY_INDEX_MAX_FILE_BYTES` | 512 000 | Skip files larger than this |
| `OLLAMA_AGENT_RUBY_INDEX_MAX_LINES` | 200 | Max result lines per search |
| `OLLAMA_AGENT_RUBY_INDEX_MAX_CHARS` | 60 000 | Max characters of index output |

**RepoScanner** (used internally by ContextPacker and indexing):

```ruby
scanner = OllamaAgent::Indexing::RepoScanner.new(root: "/project")
scanner.scan(languages: ["ruby", "yaml"])
# => [#<FileEntry path=... relative_path=... language="ruby" size=1234 modified_at=...>]
scanner.stats
# => { total_files: 142, total_bytes: 580_000, languages: { ruby: { files: 120, bytes: ... } } }
scanner.recently_modified(n: 10)
```

Languages detected: ruby, javascript, typescript, python, go, rust, java, kotlin, swift,
cpp, c, csharp, php, elixir, erlang, haskell, scala, clojure, shell, yaml, json, toml,
markdown, html, css, sql, dockerfile, terraform, proto.

---

## 16. ToolRuntime (Alternate Loop)

`OllamaAgent::ToolRuntime` is an **optional**, standalone JSON-plan execution loop
for agents that do not need the file-editing / patch workflow. The model returns a
single `{"tool":"name","args":{...}}` object per step rather than using native Ollama
tool calls.

See [TOOL_RUNTIME.md](TOOL_RUNTIME.md) for a step-by-step guide.

```ruby
class EchoTool < OllamaAgent::ToolRuntime::Tool
  def name        = "echo"
  def description = "Return msg back to caller"
  def schema      = { "type" => "object", "properties" => { "msg" => { "type" => "string" } } }
  def call(args)
    return { "status" => "done", "echo" => args["msg"] } if args["msg"] == "bye"
    { "status" => "ok", "echo" => args["msg"] }
  end
end

registry = OllamaAgent::ToolRuntime::Registry.new([EchoTool.new])
memory   = OllamaAgent::ToolRuntime::Memory.new
config   = Ollama::Config.new
OllamaAgent::OllamaConnection.apply_env_to_config(config)
client   = Ollama::Client.new(config: config)
planner  = OllamaAgent::ToolRuntime::OllamaJsonPlanner.new(client: client)

result = OllamaAgent::ToolRuntime::Loop.new(
  planner:  planner,
  registry: registry,
  executor: OllamaAgent::ToolRuntime::Executor.new,
  memory:   memory,
  max_steps: 10
).run(context: "Say hello then echo bye to finish.")
# result => { "status" => "done", "echo" => "bye" }
```

**Termination**: tool returns `{ "status" => "done" }`.
**Errors**: unknown tool → `InvalidPlanError`; too many steps → `MaxStepsExceeded`.
**Return value**: last tool result from `Executor#execute`.

---

## 17. Skills System

### Deterministic JSON-contract pipelines

Built-in skills bypass the tool-calling agent loop and return **strict JSON**
validated against a schema. Temperature is 0 by default.

| Skill class | CLI id | Output schema keys |
|-------------|--------|-------------------|
| `ArchitectureRefactorer` | `architecture_refactor` | `folder_structure`, `architecture_notes`, `refactored_code` |
| `PerformanceOptimizer` | `performance_optimizer` | `bottlenecks`, `optimizations`, `optimized_code` |
| `DebugEngineer` | `debug_engineer` | `root_cause`, `fix_description`, `fixed_code` |
| `FeatureBuilder` | `feature_builder` | `design_notes`, `implementation`, `test_outline` |

```ruby
result = OllamaAgent::Skills::ArchitectureRefactorer.new.call(
  code: File.read("lib/orders/manager.rb")
)
# => { folder_structure: [...], architecture_notes: "...", refactored_code: "..." }

# Pipeline — each skill receives prior outputs merged in
OllamaAgent::Skills::Runner.new(
  [:architecture_refactor, :performance_optimizer]
).call(code: File.read("lib/orders.rb"))

# Inject a test double
class FakeLlm
  def generate(_prompt) = '{"bottlenecks":[],"optimizations":[],"optimized_code":"x"}'
end
OllamaAgent::Skills::PerformanceOptimizer.new(llm: FakeLlm.new).call(code: "...")
```

Skills go through `OllamaAgent::Providers::Registry`, so any registered provider
(OpenAI, Anthropic, custom) is usable by passing your own `LlmClient`.

### Bundled prompt skills

Markdown context injected into the system prompt. Loaded from
`lib/ollama_agent/prompt_skills/` per `manifest.yml`.

| ID | Content |
|----|---------|
| `clean_ruby` | Clean Ruby idioms |
| `ruby_style` | Style guide (Airbnb / community) |
| `rubocop` | RuboCop rule reference |
| `solid` | SOLID design principles |
| `solid_ruby` | SOLID applied to Ruby |
| `design_patterns` | GoF patterns |
| `rspec` | RSpec best practices |
| `rails_style` | Rails conventions |
| `rails_best_practices` | Rails framework patterns |
| `code_review` | Code review checklist |
| `ollama_agent_patterns` | OllamaAgent library patterns |

**Control via CLI / env**

```bash
# disable all skills
ollama_agent ask --no-skills "..."

# include only specific skills
OLLAMA_AGENT_SKILLS_INCLUDE=ruby_style,rspec ollama_agent ask "..."

# exclude specific skills
OLLAMA_AGENT_SKILLS_EXCLUDE=rails_style,rails_best_practices ollama_agent ask "..."

# add custom skill files or directories
ollama_agent ask --skill-paths "/my/skills:~/.cursor/skills/ruby.md" "..."
```

---

## 18. Self-Improvement

### Modes

| Mode | Aliases | Description |
|------|---------|-------------|
| `analysis` | `1`, `readonly` | Read-only. Produce a report; no writes. |
| `interactive` | `2`, `fix`, `confirm` | Full tools on the live tree. Confirm each patch (unless `-y`/`--semi`). |
| `automated` | `3`, `sandbox`, `full` | Copy to temp sandbox → agent edits → run tests → optional `--apply` to merge back. |

### Automated mode workflow

1. Copy project to a temp directory (ignores `.git`, `node_modules`, `vendor`, etc.).
2. Run `Agent` with the self-improvement prompt + optional `ruby_mastery` context.
3. Restore `Gemfile`, `Gemfile.lock`, `*.gemspec`, `exe/` from source (agent cannot modify these).
4. Run **verify steps** (configurable via `--verify` / `OLLAMA_AGENT_IMPROVE_VERIFY`):
   - `syntax` — `ruby -c` on every changed `.rb` file
   - `rubocop` — RuboCop on changed files
   - `rspec` — `bundle exec rspec spec/`
5. If all checks pass and `--apply` was given: copy changed files back to the source tree.

### Ruby Mastery context (optional)

When the `ruby_mastery` gem is installed, a static-analysis section is prepended
to the improvement prompt. Disable with `--no-ruby-mastery` or `OLLAMA_AGENT_RUBY_MASTERY=0`.
Limit size with `OLLAMA_AGENT_RUBY_MASTERY_MAX_CHARS` (default 60 000).

---

## 19. Orchestrator and External Agents

Enable with `orchestrate` command or `OLLAMA_AGENT_ORCHESTRATOR=1` on `ask`.
Adds two tools to the model's tool list:

### `list_external_agents`

No parameters. Returns a table of all configured agents, their `id`, availability
on `PATH`, version string, and capabilities. Call before `delegate_to_agent` to
choose an `agent_id`.

### `delegate_to_agent`

```
agent_id         String   required  Registry id (e.g. claude_cli, gemini_cli)
task             String   required  What the external agent should do
context_summary  String   optional  Short context from your own exploration
paths            Array    optional  Relative paths to mention in the handoff
timeout_seconds  Integer  optional  Override default timeout
```

The external agent is spawned as a **non-interactive subprocess** (fixed argv, no shell).
Output is capped at `OLLAMA_AGENT_DELEGATE_MAX_OUTPUT_BYTES` (default 100 KB).
Requires user confirmation unless `-y` is set.

**Audit logging**: `OLLAMA_AGENT_DELEGATE_LOG=1` emits a structured stderr line
with agent id, argv, env key names, exit code, and duration.

### Agent registry

Default: `lib/ollama_agent/external_agents/default_agents.yml`
User override: `~/.config/ollama_agent/agents.yml` or `OLLAMA_AGENT_EXTERNAL_AGENTS_CONFIG`

```yaml
agents:
  - id: claude_cli
    name: "Claude CLI"
    path: "claude"
    version_cmd: "claude --version"
    type: "shell_command"
    supported_modes: ["chat", "ask"]
    env_api_key: "CLAUDE_API_KEY"
    timeout: 600
```

`ollama_agent agents` prints the availability table.

---

## 20. Plugin System

Extend the agent without forking the gem.

### Registration

```ruby
OllamaAgent::Plugins::Registry.register(:my_plugin) do |r|
  # Add a tool instance
  r.add_tool(MyTool.new)

  # Add system-prompt context
  r.add_prompt(name: "my_context", content: "Extra instructions …")

  # Add a tool execution policy (called before every tool call)
  r.add_policy do |tool_name, args, context|
    "rate limit exceeded" if tool_name == "http_get" && context[:call_count] > 10
    nil  # return nil to allow
  end

  # Add a provider
  r.add_provider(MyProvider.new)

  # Add a slash-command handler
  r.add_command(slash_command: "/my_cmd") { |input| "handled: #{input}" }
end
```

**Extension points**: `:tools`, `:prompts`, `:policies`, `:providers`,
`:postprocessors`, `:memory_adapters`, `:command_handlers`.

### Loader

Gems with `ollama_agent_plugin` metadata are auto-loaded at CLI startup via
`require "gem_name/ollama_agent_plugin"`.

### Registry API

```ruby
OllamaAgent::Plugins::Registry.extensions_for(:tools)  # → Array<Tools::Base>
OllamaAgent::Plugins::Registry.all_tools               # → all tool instances
OllamaAgent::Plugins::Registry.all_prompts             # → all prompt hashes
OllamaAgent::Plugins::Registry.plugin_names            # → Array<Symbol>
OllamaAgent::Plugins::Registry.reset!
```

---

## 21. Core Kernel

### Budget

```ruby
budget = OllamaAgent::Core::Budget.new(
  max_steps:    64,      # ENV OLLAMA_AGENT_MAX_TURNS
  max_tokens:   32_768,  # ENV OLLAMA_AGENT_MAX_TOKENS
  max_cost_usd: nil      # ENV OLLAMA_AGENT_MAX_COST_USD
)

budget.record_step!(tokens: 512, cost_usd: 0.001)
budget.exceeded?           # → Boolean (true if any limit hit)
budget.exceeded_reason     # → "step limit (64)" | "token limit (…)" | nil
budget.steps_exceeded?
budget.tokens_exceeded?
budget.cost_exceeded?
budget.remaining_steps     # → Integer ≥ 0
budget.reset!
budget.to_h
```

### Loop Detector

Detects tool-call loops (the model repeating the same pattern of tool calls).

```ruby
detector = OllamaAgent::Core::LoopDetector.new(
  window:    4,   # size of the repeating pattern
  threshold: 2    # how many repetitions before flagging
)

detector.record!("read_file", { path: "lib/foo.rb" })
detector.loop_detected?  # → Boolean
detector.loop_summary    # → "read_file({path:lib/foo.rb}) × 2" | nil
detector.reset!
```

### Trace Logger

```ruby
tracer = OllamaAgent::Core::TraceLogger.new(
  log_dir: ".ollama_agent/logs",
  format:  :json,    # :human | :json | :debug
  hooks:   hooks
)

tracer.start_run(query: "task")
tracer.tool_call(name: "read_file", args: {}, turn: 1, call_id: "abc")
tracer.tool_result(name: "read_file", result: "…", turn: 1, latency_ms: 12, call_id: "abc")
tracer.budget_exceeded(reason: "step limit (64)")
tracer.end_run(turns: 5, budget: budget)
```

Output: `<log_dir>/<YYYY-MM-DD>.trace.ndjson`. Enable via `--trace` / `OLLAMA_AGENT_TRACE=1`.
Run ID: `run_<8-char-hex>` (unique per `start_run`).

---

## 22. Sandbox Isolation

`OllamaAgent::Runtime::Sandbox` creates an isolated copy of the project for
`self_review --mode automated` / `improve`.

```ruby
sandbox = OllamaAgent::Runtime::Sandbox.new(
  source_root: "/my/project",
  prefix:      "ollama_agent_sandbox"
)

sandbox.setup!               # copy to temp dir
sandbox.path                 # → "/tmp/ollama_agent_sandbox_XXXX"
sandbox.changed_files        # → ["lib/foo.rb", "spec/foo_spec.rb"]
sandbox.deleted_files        # → []
sandbox.sync_back!(target: "/my/project", only_files: ["lib/foo.rb"])
sandbox.teardown!            # delete temp dir
sandbox.use { |s| ... }     # setup + yield + teardown (ensure)
```

**Directories skipped when copying**:
`.git`, `.svn`, `.hg`, `.bzr`, `node_modules`, `vendor`, `.bundle`, `tmp`, `log`,
`coverage`, `.nyc_output`, `dist`, `build`, `out`, `target`, `__pycache__`,
`.pytest_cache`, `.mypy_cache`, `.tox`, `venv`, `env`, `.venv`, `.ollama_agent`,
`.idea`, `.vscode`, `.cursor`.

---

## 23. Environment Variables

All variables prefixed `OLLAMA_AGENT_*` unless noted.

### Core behaviour

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `OLLAMA_AGENT_MODEL` | String | ollama-client default | Chat model name |
| `OLLAMA_AGENT_ROOT` | String | `Dir.pwd` | Project root for all tools |
| `OLLAMA_AGENT_MAX_TURNS` | Integer | 64 | Max agent iterations per run |
| `OLLAMA_AGENT_MAX_TOKENS` | Integer | 32 768 | Context window budget |
| `OLLAMA_AGENT_MAX_COST_USD` | Float | nil | Cost limit (cloud models) |
| `OLLAMA_AGENT_TIMEOUT` | Integer | 120 | HTTP read/open timeout (seconds) |
| `OLLAMA_AGENT_MAX_RETRIES` | Integer | 3 | HTTP retry attempts (0 = disable) |
| `OLLAMA_AGENT_RETRY_BASE_DELAY` | Float | 1.0 | Base delay for exponential backoff (seconds) |
| `OLLAMA_AGENT_STRICT_ENV` | Boolean | 0 | Raise `ConfigurationError` on invalid numeric env values |

### Thinking / reasoning

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `OLLAMA_AGENT_THINK` | String | nil | `true`/`false`/`high`/`medium`/`low` |
| `OLLAMA_AGENT_GPT_OSS_THINK` | String | `medium` | Thinking level when `think=true` on GPT-OSS models |

### Streaming and display

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `OLLAMA_AGENT_STREAM` | Boolean | 0 | Live token streaming to stdout |
| `OLLAMA_AGENT_COLOR` | Boolean | 1 | ANSI colors (disabled by `NO_COLOR`) |
| `OLLAMA_AGENT_MARKDOWN` | Boolean | 1 | Markdown formatting of assistant replies |
| `OLLAMA_AGENT_THINKING_STYLE` | String | `compact` | `compact` \| `framed` |
| `OLLAMA_AGENT_THINKING_MARKDOWN` | Boolean | 0 | Render thinking text as Markdown |
| `NO_COLOR` | Boolean | unset | Disable all colors (standard) |

### Observability

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `OLLAMA_AGENT_DEBUG` | Boolean | 0 | Verbose debug output to stderr |
| `OLLAMA_AGENT_TRACE` | Boolean | 0 | Structured trace NDJSON under `.ollama_agent/logs/` |
| `OLLAMA_AGENT_AUDIT` | Boolean | 0 | Structured audit NDJSON under `.ollama_agent/logs/` |
| `OLLAMA_AGENT_AUDIT_LOG_PATH` | String | `.ollama_agent/logs` | Audit log directory |
| `OLLAMA_AGENT_AUDIT_MAX_RESULT_BYTES` | Integer | 4 096 | Truncate tool result in audit log |
| `OLLAMA_AGENT_LOG_LEVEL` | String | `warn` | Logger level: `debug`/`info`/`warn`/`error` |

### Skills and prompts

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `OLLAMA_AGENT_SKILLS` | Boolean | 1 | Enable bundled prompt skills |
| `OLLAMA_AGENT_SKILLS_INCLUDE` | String | nil | CSV skill ids to include (omit = all) |
| `OLLAMA_AGENT_SKILLS_EXCLUDE` | String | nil | CSV skill ids to exclude |
| `OLLAMA_AGENT_SKILL_PATHS` | String | nil | Colon-separated extra `.md` files/dirs |
| `OLLAMA_AGENT_EXTERNAL_SKILLS` | Boolean | 1 | Include content from `SKILL_PATHS` |
| `OLLAMA_AGENT_SKILL_MODEL` | String | nil | Model for deterministic skill pipeline |

### Tools and search

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `OLLAMA_AGENT_PARSE_TOOL_JSON` | Boolean | 0 | Parse tool JSON from assistant text (fallback) |
| `OLLAMA_AGENT_MAX_READ_FILE_BYTES` | Integer | 2 097 152 | Max bytes for full `read_file` |
| `OLLAMA_AGENT_SEARCH_TIMEOUT_SEC` | Integer | 120 | Timeout for ripgrep/grep searches |
| `OLLAMA_AGENT_RG_PATH` | String | *(PATH)* | Absolute path to `rg` binary |
| `OLLAMA_AGENT_GREP_PATH` | String | *(PATH)* | Absolute path to `grep` fallback |
| `OLLAMA_AGENT_PATCH_RISK_MAX_DIFF_LINES` | Integer | 80 | Line count before diff is "large" |

### Ruby indexing (Prism)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `OLLAMA_AGENT_INDEX_REBUILD` | Boolean | 0 | Change value to force index rebuild |
| `OLLAMA_AGENT_RUBY_INDEX_MAX_FILES` | Integer | 5 000 | Max `.rb` files per index build |
| `OLLAMA_AGENT_RUBY_INDEX_MAX_FILE_BYTES` | Integer | 512 000 | Skip files larger than this |
| `OLLAMA_AGENT_RUBY_INDEX_MAX_LINES` | Integer | 200 | Max result lines per search |
| `OLLAMA_AGENT_RUBY_INDEX_MAX_CHARS` | Integer | 60 000 | Max characters of index output |

### Orchestrator and delegation

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `OLLAMA_AGENT_ORCHESTRATOR` | Boolean | 0 | Enable external-agent delegation tools |
| `OLLAMA_AGENT_EXTERNAL_AGENTS_CONFIG` | String | `~/.config/ollama_agent/agents.yml` | Custom agents.yml path |
| `OLLAMA_AGENT_DELEGATE_MAX_OUTPUT_BYTES` | Integer | 102 400 | Cap on delegated task output |
| `OLLAMA_AGENT_DELEGATE_LOG` | Boolean | 0 | Structured stderr log per delegation |

### Self-improvement

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `OLLAMA_AGENT_RUBY_MASTERY` | Boolean | 1 | Prepend static-analysis context (`ruby_mastery` gem) |
| `OLLAMA_AGENT_RUBY_MASTERY_MAX_CHARS` | Integer | 60 000 | Truncate ruby_mastery context |
| `OLLAMA_AGENT_IMPROVE_VERIFY` | String | `rspec` | Comma-separated verify steps |

### Providers

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `OLLAMA_BASE_URL` | String | `http://localhost:11434` | Ollama API base URL |
| `OLLAMA_API_KEY` | String | nil | Ollama Cloud API key |
| `OLLAMA_AGENT_CLOUD_CATALOG_URL` | String | `https://ollama.com/api/tags` | Cloud model catalog |
| `OPENAI_API_KEY` | String | nil | OpenAI API key (auto-detected by `--provider auto`) |
| `ANTHROPIC_API_KEY` | String | nil | Anthropic API key (auto-detected by `--provider auto`) |

### Configuration and dotenv

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `OLLAMA_AGENT_USE_LOCAL_DOTENV` | Boolean | 0 | Load `.env` from project root instead of `~/.config` |
| `OLLAMA_AGENT_DOTENV_PATH` | String | nil | Custom `.env` path |
| `XDG_CONFIG_HOME` | String | `~/.config` | Standard XDG config directory |
| `OLLAMA_AGENT_TUI_GOD_MODE` | Boolean | 0 | Auto-select first TUI option (dangerous) |
| `OLLAMA_AGENT_PLUGINS` | String | nil | Colon-separated plugin gem names to load |

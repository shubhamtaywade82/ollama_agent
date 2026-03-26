# Production-Ready `ollama_agent` — Design Spec

**Date:** 2026-03-26
**Status:** Approved
**Approach:** Additive Layers (B) — existing core untouched; six new layers stacked on top

---

## 1. Goals

Transform `ollama_agent` v0.1.x from a solid single-developer CLI tool into a production-ready gem that serves three personas simultaneously:

- **Solo developer** — maximum autonomy, streaming, session resume, retries
- **Team/shared** — audit logs, safe defaults, structured observability
- **Library consumer** — stable `OllamaAgent::Runner` API, extensible tool registry, YARD docs

All new capabilities are **backward-compatible** and **opt-in** via new flags/env vars. No existing CLI flags, env vars, or `Agent.new` kwargs change.

---

## 2. Architecture Overview

```
CLI / Runner.run(query)
  → Session::Store.resume (if --resume) or Session::Store.new session header
  → Agent#run
      → Context::Manager.trim(messages)
      → OllamaConnection (with Resilience::RetryMiddleware)
          → Ollama::Client#chat (streaming: true when subscribed)
              → Streaming::Hooks.emit(:on_token, chunk)
      → Tools::Registry.execute(name, args)
          → Resilience::AuditLogger.log_tool_call(...)
      → repeat until no tool calls
  → Session::Store.save(messages)
```

### New directory structure

```
lib/ollama_agent/
├── agent.rb                    ← unchanged public API; gains hooks + context manager wiring
├── cli.rb                      ← gains --stream, --session, --resume flags
├── sandboxed_tools.rb          ← gains write_file; case replaced by Registry dispatch
├── tools_schema.rb             ← gains write_file schema entry
│
├── tools/
│   ├── registry.rb             ← OllamaAgent::Tools.register / .execute / .schema_for
│   ├── built_in.rb             ← re-registers existing 4 tools + write_file via registry
│   └── base.rb                 ← optional structured tool base class
│
├── context/
│   ├── manager.rb              ← token budget, sliding window trim, summarize hook
│   └── token_counter.rb        ← char-estimate default; tiktoken_ruby plug-in when present
│
├── session/
│   ├── store.rb                ← save/load NDJSON under .ollama_agent/sessions/
│   └── session.rb              ← session metadata + message envelope
│
├── streaming/
│   ├── hooks.rb                ← on_token/on_chunk/on_tool_call/on_tool_result/on_complete/on_error
│   └── console_streamer.rb     ← default CLI subscriber for live token output
│
├── resilience/
│   ├── retry_middleware.rb     ← exponential backoff on TimeoutError / HTTP 5xx / 429
│   └── audit_logger.rb        ← NDJSON to .ollama_agent/logs/ behind OLLAMA_AGENT_AUDIT=1
│
└── runner.rb                   ← OllamaAgent::Runner — stable library facade
```

---

## 3. Layer 1 — Tool Registry + `write_file`

### 3.1 `write_file` tool

- **Purpose:** create or overwrite a file under project root with full UTF-8 content
- **Schema:** `{ path: String (required), content: String (required) }`
- **Guards:** same `path_allowed?` sandbox as `edit_file`; blocked in read-only mode; confirmation flow when `confirm_patches: true` (prompt text: "Write file? (y/n)" — distinct from patch prompt)
- **Audit:** logged as `write_applied` event when audit enabled
- **Agent prompt addition:** "use `write_file` for new files or full rewrites; prefer `edit_file` for surgical changes"

### 3.2 `Tools::Registry`

```ruby
# Public API
OllamaAgent::Tools.register(:name, schema: { ... }) { |args, context:| ... }
OllamaAgent::Tools.execute(name, args, context:)
OllamaAgent::Tools.all_schemas(read_only:, orchestrator:)
```

- Hash-based dispatch replaces `case` in `SandboxedTools#execute_tool`
- Built-in tools registered at require-time in `tools/built_in.rb`
- `context` hash passes `{ root:, read_only:, orchestrator: }` to every handler
- Custom tools registered before `Runner.build` are automatically injected into the model's tool list
- `TOOLS` / `READ_ONLY_TOOLS` constants kept as backward-compatible aliases

### 3.3 Constraints

- Custom tool handlers must respect `context[:read_only]`; registry enforces this for write-class built-ins
- No metaprogramming — plain `Hash` keyed by string name; explicit registration only
- Adding a tool does not require changes to `agent.rb`, `cli.rb`, or `tools_schema.rb`

---

## 4. Layer 2 — Context Manager

### 4.1 `Context::Manager`

Inserted into `Agent#execute_agent_turns` before every `chat` call. Never mutates messages in place — returns a trimmed copy.

**Configuration:**

| Env var | Keyword | Default |
|---------|---------|---------|
| `OLLAMA_AGENT_MAX_TOKENS` | `max_tokens:` | `8_192` |
| `OLLAMA_AGENT_CONTEXT_SUMMARIZE` | `context_summarize:` | `false` |

**Trim strategies:**

| Strategy | Behavior |
|----------|----------|
| Sliding window (default) | Drop oldest non-system message pairs until under `SUMMARY_THRESHOLD` (85%) of budget |
| Summarize (`context_summarize: true`) | Ask model to summarize dropped segment; inject as system message |

### 4.2 Invariants

- System prompt is **never** trimmed
- The most recent `user` message is **never** trimmed
- `tool` result messages are trimmed together with their preceding `assistant` message (never orphaned)
- When a single message exceeds budget: truncate with `[truncated by context manager]` suffix — same pattern as `Runner#truncate`

### 4.3 `Context::TokenCounter`

- Default: `chars / 4` (safe zero-dep estimate)
- Auto-upgrades to `tiktoken_ruby` when present in host bundle (`require` rescue'd)

---

## 5. Layer 3 — Session Persistence

### 5.1 Storage format

**Location:** `.ollama_agent/sessions/<YYYY-MM-DD>T<HH-MM-SS>_<id>.ndjson` under project root

**File format** (NDJSON — one JSON object per line):
```jsonc
// Line 1: session header
{"v":1,"id":"abc123","model":"gpt-oss:120b-cloud","root":"/proj","started_at":"2026-03-26T14:32:01Z"}
// Subsequent lines: message envelopes
{"role":"user","content":"Refactor the CLI","ts":"2026-03-26T14:32:02Z"}
{"role":"assistant","content":"I'll start by reading cli.rb...","tool_calls":[...],"ts":"..."}
{"role":"tool","name":"read_file","content":"...","ts":"..."}
```

### 5.2 `Session::Store` API

```ruby
Session::Store.save(session_id:, root:, message:)      # append one message (crash-safe)
Session::Store.load(session_id:, root:)                 # → Array<Hash>
Session::Store.list(root:)                              # → Array<SessionMeta>, newest first
Session::Store.resume(session_id:, root:)               # → messages Array for Agent seeding
```

### 5.3 CLI integration

```bash
ollama_agent ask --session my-refactor "Start refactoring the CLI"
ollama_agent ask --session my-refactor --resume
ollama_agent ask -i --session my-refactor --resume     # REPL + resume
ollama_agent sessions                                   # list sessions table
```

`--resume` without `--session` resumes the most recent session for the current root.

### 5.4 Constraints

- Scoped to project root — not global
- Messages appended after each turn, not batch-written at end (crash-safe)
- `Context::Manager` trims loaded session messages before first chat call
- Files are plain text: human-readable, `grep`-able, `jq`-able

---

## 6. Layer 4 — Streaming

### 6.1 `Streaming::Hooks`

Lightweight event bus — plain Ruby, zero deps.

```ruby
hooks = OllamaAgent::Streaming::Hooks.new
hooks.on(:on_token)       { |p| print p[:token] }
hooks.on(:on_tool_call)   { |p| log(p[:name]) }
hooks.emit(:on_token, { token: "hello", turn: 1 })
```

**Events:**

| Event | Payload keys | When fired |
|-------|-------------|------------|
| `on_token` | `token`, `turn` | Each streamed token |
| `on_chunk` | `delta`, `turn` | Each raw ollama-client chunk |
| `on_tool_call` | `name`, `args`, `turn` | Before tool executes |
| `on_tool_result` | `name`, `result`, `turn` | After tool returns |
| `on_complete` | `messages`, `turns` | Loop finished |
| `on_error` | `error`, `turn` | Unhandled error in loop |
| `on_retry` | `error`, `attempt`, `delay_ms` | RetryMiddleware fires |

Multiple subscribers per event are supported. All seven events are members of `Hooks::EVENTS`; `on_retry` is included even though it is fired by `RetryMiddleware` (not `Agent`) — the hooks bus is shared across layers.

### 6.2 `Streaming::ConsoleStreamer`

Default CLI subscriber. Auto-attached when stdout is a TTY and `OLLAMA_AGENT_STREAM=1` or `--stream` is passed.

### 6.3 `Agent` integration

```ruby
def chat_assistant_message(messages)
  if @hooks.subscribed?(:on_token)
    stream_assistant_message(messages)   # chunk-by-chunk path
  else
    block_assistant_message(messages)    # existing behavior — 100% unchanged
  end
end
```

Non-streaming path is the default. Streaming is opt-in.

---

## 7. Layer 5 — Resilience

### 7.1 `Resilience::RetryMiddleware`

Wraps `Ollama::Client#chat`. Applied in `OllamaConnection` / `Agent#build_default_client`.

**Retry policy:**

| Condition | Max attempts | Backoff |
|-----------|-------------|---------|
| `Ollama::TimeoutError` | 3 | Exponential: 2s, 4s, 8s + jitter |
| HTTP 503 / 429 | 3 | Same |
| `Errno::ECONNREFUSED` | 2 | 5s fixed |
| HTTP 4xx | 0 (fail immediately) | — |
| Tool errors | 0 (never retry) | — |

**Configuration:**

| Env var | Keyword | Default |
|---------|---------|---------|
| `OLLAMA_AGENT_MAX_RETRIES` | `max_retries:` | `3` |
| `OLLAMA_AGENT_RETRY_BASE_DELAY` | — | `2.0` seconds |

Set `OLLAMA_AGENT_MAX_RETRIES=0` to restore current no-retry behavior.

Fires `on_retry` hook on each attempt so AuditLogger and CLI can surface it.

### 7.2 `Resilience::AuditLogger`

**Location:** `.ollama_agent/logs/YYYY-MM-DD.ndjson` under project root

**Activation:** `OLLAMA_AGENT_AUDIT=1` or `audit: true` in `Runner.build`

**Logged events:**

```jsonc
{"ts":"...","event":"agent_start","model":"...","root":"...","session":"..."}
{"ts":"...","event":"tool_call","name":"read_file","args":{"path":"lib/cli.rb"},"turn":1}
{"ts":"...","event":"tool_result","name":"read_file","bytes":4210,"turn":1,"duration_ms":3}
{"ts":"...","event":"edit_applied","path":"lib/cli.rb","diff_lines":12,"turn":2}
{"ts":"...","event":"write_applied","path":"lib/new_file.rb","bytes":340,"turn":3}
{"ts":"...","event":"http_retry","attempt":2,"error":"TimeoutError","delay_ms":4213}
{"ts":"...","event":"agent_complete","turns":4,"duration_ms":38210}
```

**Constraints:**
- Log writes are non-blocking best-effort (`rescue StandardError` around every write)
- Log dir created automatically on first write
- Daily rotation (one file per date)
- `OLLAMA_AGENT_AUDIT_MAX_RESULT_BYTES=4096` caps tool result bodies in log (default: 4096)
- Subscribes to `Streaming::Hooks` — no coupling to `Agent` internals

---

## 8. Layer 6 — Library API (`OllamaAgent::Runner`)

### 8.1 `Runner.build` factory

```ruby
OllamaAgent::Runner.build(
  root:              Dir.pwd,       # project root
  model:             nil,           # OLLAMA_AGENT_MODEL or ollama-client default
  stream:            false,         # enable streaming output
  session_id:        nil,           # named session
  resume:            false,         # load prior session messages
  max_tokens:        nil,           # context budget (OLLAMA_AGENT_MAX_TOKENS)
  context_summarize: false,         # summarize vs sliding-window trim
  max_retries:       3,             # OLLAMA_AGENT_MAX_RETRIES
  audit:             false,         # OLLAMA_AGENT_AUDIT
  read_only:         false,         # disable edit_file + write_file
  skills_enabled:    true,          # bundled prompt skills (matches Agent kwarg)
  skill_paths:       nil,           # extra .md paths
  confirm_patches:   true,          # prompt before applying patches
  orchestrator:      false,         # enable external agent delegation
  think:             nil,           # thinking mode
  http_timeout:      nil            # OLLAMA_AGENT_TIMEOUT
) → OllamaAgent::Runner
```

### 8.2 Instance interface

```ruby
runner.hooks       # → Streaming::Hooks — attach subscribers before run
runner.session     # → Session::Session or nil
runner.run(query)  # → nil — execute one query
runner.start_repl  # → nil — interactive REPL (blocks)
```

### 8.3 SemVer contract (from 0.2.0)

| Surface | Stability |
|---------|-----------|
| `Runner.build` + `#run` + `#hooks` + `#session` | **Stable** |
| `OllamaAgent::Tools.register` | **Stable** |
| All `OLLAMA_AGENT_*` env vars | **Stable** |
| `OllamaAgent::CLI` flags | **Stable** |
| `OllamaAgent::Agent` kwargs | **Supported** (internal-friendly) |
| `Context/Session/Streaming/Resilience` internals | **Internal** |

### 8.4 Documentation

- `docs/ARCHITECTURE.md` — layer diagram + data flow
- `docs/TOOLS.md` — custom tool registration guide with examples
- `docs/SESSIONS.md` — session persistence usage and file format
- YARD `@param`/`@return` on all public `Runner`, `Tools.register`, and `Hooks#on` methods

---

## 9. New Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `OLLAMA_AGENT_STREAM` | Enable streaming output | off |
| `OLLAMA_AGENT_MAX_TOKENS` | Context window budget | `8192` |
| `OLLAMA_AGENT_CONTEXT_SUMMARIZE` | Use summarize vs sliding-window trim | off |
| `OLLAMA_AGENT_MAX_RETRIES` | Max HTTP retry attempts (0 = disable) | `3` |
| `OLLAMA_AGENT_RETRY_BASE_DELAY` | Base backoff delay in seconds | `2.0` |
| `OLLAMA_AGENT_AUDIT` | Enable structured audit logging | off |
| `OLLAMA_AGENT_AUDIT_LOG_PATH` | Override audit log directory | `<root>/.ollama_agent/logs/` |
| `OLLAMA_AGENT_AUDIT_MAX_RESULT_BYTES` | Cap tool result bodies in audit log | `4096` |

---

## 10. New CLI Flags

All new flags added to `ask`, `orchestrate`, `self_review`, `improve` where applicable:

| Flag | Purpose |
|------|---------|
| `--stream` | Enable streaming token output |
| `--session NAME` | Named session id |
| `--resume` | Load prior session messages before running |
| `--max-tokens N` | Context window budget |
| `--max-retries N` | HTTP retry limit |
| `--audit` | Enable audit logging for this run |

New top-level command: `ollama_agent sessions` — list sessions for current project root.

---

## 11. Test Coverage Requirements

Each new layer ships with specs:

| Layer | Required specs |
|-------|---------------|
| Tool Registry | register, execute, all_schemas; custom tool injection; read-only guard |
| `write_file` | create, overwrite, path sandbox, read-only block, confirmation |
| Context::Manager | trim sliding window, trim summarize, invariants (system/last-user never trimmed) |
| Session::Store | save, load, list, resume, crash-safe append |
| Streaming::Hooks | on/emit, multiple subscribers, unknown event no-op |
| ConsoleStreamer | attaches correct handlers |
| RetryMiddleware | retries on timeout/503/429, no retry on 4xx, max attempts, backoff |
| AuditLogger | writes NDJSON, best-effort (write failure doesn't raise), daily rotation |
| Runner | build factory, run, hooks, session wiring; integration smoke test |

Existing specs must remain green with zero changes.

---

## 12. Implementation Order

Each layer is an independently shippable PR:

1. **Tool Registry + `write_file`** — foundational; unblocks custom tools
2. **Streaming + Hooks** — unblocks AuditLogger (shares hook bus)
3. **Resilience (Retry + AuditLogger)** — depends on Hooks
4. **Context::Manager** — independent
5. **Session::Store** — independent; integrates with Context::Manager
6. **Runner + Library API + YARD docs** — integrates all layers; final PR

## [Unreleased]

### Documentation

- **README:** New **Reasoning / thinking output** section—how to set `think` (including **GPT-OSS** `low`/`medium`/`high`), streaming vs one-shot, display env vars, troubleshooting when **Thinking** is missing, Gemma-style tags, and **`Runner.build`** example. **`OLLAMA_AGENT_STREAM`** and GPT-OSS notes added to the environment table; Ollama Cloud example sets **`OLLAMA_AGENT_THINK`**.

### Fixed

- **Thinking display:** Coerce non-string `message.thinking` from the API (e.g. array-shaped chunks) before deciding whether reasoning is present (`GemmaThoughtContentParser.merge_into_message_data!` + `ChatStreamThinkingFormat`). After a **streaming** chat completion, run the same merge so content-embedded reasoning tags still split into **Thinking** / **Assistant**.

## [1.0.0] - 2026-04-11

First **stable** release under [Semantic Versioning](https://semver.org/): within the **`1.x`** series, the documented public Ruby API and CLI behavior are intended to remain **backwards compatible** except where called out in the changelog.

### Changed

- **CLI default:** `ollama_agent` with no subcommand runs **`ask`** with the **interactive TUI** when no query is given (same as `ollama_agent ask` with no query). Use **`ask -i` without `--tui`** for the plain line REPL, **`ask "…"`** for a one-shot task, or another subcommand (`self_review`, `sessions`, …) for other workflows.

### Breaking changes (from 0.3.x)

- **`tty-spinner` removed** from the gem; **`OllamaAgent::TUI`** no longer exposes `with_spinner`, `dismiss_progress_spinner`, `pause_progress_for_user_prompt`, or `resume_progress_after_user_prompt`. Code that called those methods or relied on the transitive `tty-spinner` dependency must be updated.
- **`Agent#chat_assistant_message`** uses the streaming HTTP path **only** when something subscribes to **`on_token`** (not merely **`on_thinking`**). Integrations that registered only `on_thinking` expecting streamed chat must also subscribe to `on_token` or use another supported hook.

### Fixed

- TUI slash-command tab completion no longer raises `FrozenError` when editing a completed frozen candidate (e.g. `/help`).

## [0.3.0] - 2026-04-06

### Added

- `ToolRuntime` — JSON plan loop for custom tools (`OllamaJsonPlanner`, registry, executor); see `docs/TOOL_RUNTIME.md`
- Optional **ruby_mastery** context for `self_review` / `improve` (`OLLAMA_AGENT_RUBY_MASTERY`, `--no-ruby-mastery`)
- `OllamaAgent::ModelEnv` — shared model name resolution from environment
- `OllamaAgent::GlobalDotenv` — load repo-root `.env` after `ollama_client` so CLI picks up `OLLAMA_AGENT_*` without extra exports
- Self-improvement automated mode: `--verify` (`syntax`, `rubocop`, `rspec`), `OLLAMA_AGENT_IMPROVE_VERIFY`, `--stream`, and a success message when `--apply` was not used
- External agents / argv expansion and related orchestration refinements

### Changed

- `SearchBackend` finds `rg` / `grep` by scanning `PATH` (avoids relying on a `command` executable on trimmed `PATH`)

### Fixed

- `SelfImprovement::Improver#run` accepts `max_tokens` and `context_summarize` from the CLI (Ruby 3 keyword compatibility)

## [0.2.0] - 2026-03-26

### Added

- `write_file` tool — create or overwrite files (complements `edit_file` for surgical diffs)
- `OllamaAgent::Tools.register` — extensible tool registry for library consumers
- `Streaming::Hooks` — event bus (`on_token`, `on_tool_call`, `on_tool_result`, `on_complete`, `on_error`, `on_retry`)
- `--stream` / `OLLAMA_AGENT_STREAM=1` — live streaming token output
- `Resilience::RetryMiddleware` — exponential backoff on timeout/503/429 (default 3 retries)
- `Resilience::AuditLogger` — NDJSON audit log under `.ollama_agent/logs/` (`--audit` / `OLLAMA_AGENT_AUDIT=1`)
- `Context::Manager` — sliding-window token trim before each chat call (`OLLAMA_AGENT_MAX_TOKENS`)
- `Session::Store` — crash-safe NDJSON session persistence (`--session`, `--resume`)
- `ollama_agent sessions` — list saved sessions
- `OllamaAgent::Runner` — stable public library facade with SemVer contract from 0.2.0
- `docs/ARCHITECTURE.md`, `docs/TOOLS.md`, `docs/SESSIONS.md`

### Changed

- `READ_ONLY_TOOLS` now excludes both `edit_file` and `write_file`
- `Agent` now exposes `#hooks` (`Streaming::Hooks`) and `#session_id`

### New environment variables

- `OLLAMA_AGENT_STREAM`, `OLLAMA_AGENT_MAX_TOKENS`
- `OLLAMA_AGENT_MAX_RETRIES`, `OLLAMA_AGENT_RETRY_BASE_DELAY`
- `OLLAMA_AGENT_AUDIT`, `OLLAMA_AGENT_AUDIT_LOG_PATH`

## [0.1.0] - 2026-03-21

- Initial release

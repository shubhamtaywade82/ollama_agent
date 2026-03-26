## [Unreleased]

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

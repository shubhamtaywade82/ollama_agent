# Architecture

ollama_agent is a layered gem. Each layer is independently opt-in.

## Data Flow

```
CLI / Runner.run(query)
  → Session::Store.resume (if --resume)
  → Agent#run
      → Context::Manager.trim(messages)
      → OllamaConnection + Resilience::RetryMiddleware
          → Ollama::Client#chat
              → Streaming::Hooks.emit(:on_token, ...)
      → Tools::Registry / SandboxedTools.execute_tool(name, args)
          → Resilience::AuditLogger (via hooks)
      → Session::Store.save (after each turn)
  → Streaming::Hooks.emit(:on_complete, ...)
```

## Layers

| Layer | Files | Opt-in via |
|-------|-------|-----------|
| Core agent | `agent.rb`, `agent/*.rb`, `sandboxed_tools.rb`, `sandboxed_tools/*.rb` | Always on |
| Path sandbox | `path_sandbox.rb` | Always on for file/search/list tools |
| Env helpers | `env_config.rb` | Used by `Agent` and `SandboxedTools` for numeric ENV parsing |
| User prompts | `user_prompt.rb` | Injectable stdin/stdout (default TTY); `Runner.build(stdin:, stdout:)` |
| Tool Registry | `tools/registry.rb` | `OllamaAgent::Tools.register(...)` |
| Streaming | `streaming/hooks.rb`, `streaming/console_streamer.rb` | `--stream` / `OLLAMA_AGENT_STREAM=1` |
| Resilience | `resilience/retry_middleware.rb`, `resilience/audit_logger.rb` | On by default (retries); `--audit` for logging |
| Context Manager | `context/manager.rb` | `--max-tokens N` / `OLLAMA_AGENT_MAX_TOKENS` |
| Session | `session/store.rb` | `--session NAME` |
| Runner API | `runner.rb` | `require "ollama_agent"; OllamaAgent::Runner.build(...)` |

## Path sandbox (symlinks)

Tool paths are checked with `PathSandbox.allowed?`: after expanding relative to the project root, `File.realpath` must stay under `File.realpath(project_root)`. A symlink **inside** the repo that points **outside** is rejected, so the model cannot follow `link → /etc` style escapes. Paths that do not yet exist are allowed only when every existing parent directory resolves under the real root (see `nonexistent_path_allowed_under_root?` in `path_sandbox.rb`).

## ToolRuntime (parallel path)

The coding agent flow above is **not** the only entry point. `OllamaAgent::ToolRuntime` implements a separate **JSON plan → tool → memory** loop for custom `Tool` classes and injectable planners. It is **not** used by `exe/ollama_agent`. See [TOOL_RUNTIME.md](TOOL_RUNTIME.md).

---
name: ollama-agent-patterns
description: >-
  Blueprint for building a CLI Ollama-based coding agent (Ruby gem) with design
  patterns and judicious metaprogramming—Facade, Template Method, Factory/Registry,
  Builder, Adapter, Proxy, Command, Observer, Strategy, State, and tool DSLs. Use
  when working on ollama_agent, ollama-client integration, tools, LLM adapters,
  prompts, streaming, patch application, or when the user asks for agent
  architecture, extensibility, registries, or Ruby metaprogramming for agents.
---

# Ollama Agent: Patterns & Metaprogramming

## When to apply

- Designing or refactoring `ollama_agent` (CLI agent loop, tools, LLM layer).
- Adding tools, backends, streaming hooks, or patch strategies.
- Choosing where new code belongs (see layout table below).

## Principles

1. **Start simple** — introduce Factory, State, Strategy, etc. when duplication or branching pain appears; do not front-load every pattern.
2. **Core loop stays explicit** — the main agent loop should remain readable; hide complexity behind named collaborators (`Adapter`, `PromptBuilder`, `ToolCommand`), not clever `send` chains.
3. **Metaprogramming for boundaries** — registration and DSLs at tool/plugin edges; avoid dynamic dispatch in error handling and hot paths unless measured.
4. **Workspace rules** — tool schemas validated before execution; actions loggable/replayable; no hardcoded model names (runtime config).

## Pattern map

| Area | Patterns | Role |
|------|-----------|------|
| **Agent** | Facade, Template Method | Single entry (`run`); fixed loop skeleton with overridable steps. |
| **Tools** | Factory Method, Command, Registry | Discover/instantiate tools; optional undo/replay via command objects. |
| **LLM** | Adapter, Proxy | Swap backends; add logging, rate limits, metrics without changing core client. |
| **Client lifetime** | Singleton (optional) | One process-wide client when appropriate; prefer explicit DI for tests. |
| **Prompts** | Builder | Fluent construction of messages + tools + options. |
| **Streaming** | Observer | Multiple subscribers for tokens (UI, logs, metrics). |
| **Patches** | Strategy | Swap `patch` vs Ruby-native apply, etc. |
| **Conversation** | State | Phases (idle, awaiting tools, confirmation) without giant `if/else`. |

## Target gem layout

```
ollama_agent/
├── exe/ollama_agent
├── lib/ollama_agent.rb
└── lib/ollama_agent/
    ├── agent.rb              # Facade + Template Method
    ├── cli.rb
    ├── prompt_builder.rb   # Builder
    ├── tool_registry.rb    # name → class map (often class-level, not Singleton)
    ├── tools/base.rb       # inherited hook / DSL; concrete tools
    ├── tools/
    ├── llm/base_adapter.rb
    ├── llm/ollama_adapter.rb
    ├── llm/logging_proxy.rb
    ├── commands/tool_command.rb
    ├── observers/
    ├── strategies/         # patch strategies
    └── states/             # optional; add when phase logic grows
```

## Where things live

| Concept | Typical file/dir |
|---------|-------------------|
| Facade / loop skeleton | `lib/ollama_agent/agent.rb` |
| Builder | `lib/ollama_agent/prompt_builder.rb` |
| Registry + `inherited` | `lib/ollama_agent/tools/base.rb` + `tool_registry.rb` |
| Adapter / Proxy | `lib/ollama_agent/llm/` |
| Command | `lib/ollama_agent/commands/tool_command.rb` |
| Observer | `lib/ollama_agent/observers/` |
| Strategy | `lib/ollama_agent/strategies/` |
| State | `lib/ollama_agent/states/` |

## Loading order

- Require `version`, then foundational pieces (`tool_registry`, `tools/base`), then `Dir.glob` tools (ensure subclasses load after `Base`), then LLM, commands, agent, CLI.
- See snippet in [reference.md](reference.md).

## Metaprogramming (use sparingly)

- **`inherited`** — auto-register tool subclasses when files load.
- **Tool DSL** — `tool :name, "description" do ... end` at class level; keep implementation thin; test generated behavior.
- **`send` / hooks** — `on_#{event}` only when subscribers are optional and names are fixed; prefer explicit methods for public API.

## When to avoid heavy metaprogramming

- Main agent loop and error handling — prefer explicit code.
- Performance-sensitive inner loops — measure before dynamic dispatch.
- Public APIs — stable, documented methods over hidden DSL magic.

## Full code examples

See [reference.md](reference.md) for registry, `PromptBuilder`, adapters, proxy, command, observer, strategy, state, template-method skeleton, DSL sketch, and a corrected “putting it together” example.

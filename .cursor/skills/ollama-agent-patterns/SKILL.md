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

# Skill: Ollama Agent — Design Patterns & Metaprogramming

## 1. Overview

Blueprint for a **CLI coding agent** (e.g. `ollama_agent`) that uses **ollama-client** to chat with tools: read/search files, apply small unified diffs from natural language. Patterns keep the design **extensible and maintainable** without front-loading complexity.

## 2. Core components & patterns

| Component | Pattern(s) | Purpose |
|-----------|------------|---------|
| **Agent** | Facade, Template Method | Simple API (`run`); skeleton loop with overridable steps. |
| **Tools** | Factory Method, Command, Registry | Load/execute tools; optional logging/replay/undo. |
| **LLM client** | Adapter, (optional) Proxy | Swap backends; logging/metrics without forking core. |
| **Prompts** | Builder | Fluent construction of messages + tools + options. |
| **Streaming** | Observer | Multiple subscribers for tokens (UI, logs). |
| **Patch application** | Strategy | Swap `patch(1)` vs Ruby-native apply, etc. |
| **Conversation** | State | Phases (idle, tools, confirmation) without giant `if/else`. |

**Client lifetime:** **Singleton** is optional. Prefer **injectable** `Ollama::Client` (or adapter) for tests and per-run config (`timeout`, `base_url`, `api_key`).

## 3. Principles

1. **Start simple** — add Factory, State, Strategy when duplication or branching hurts; do not adopt every pattern up front.
2. **Core loop stays explicit** — readable `run` / tool loop; collaborators (`Adapter`, `PromptBuilder`, `ToolCommand`) hide detail, not `send` spaghetti.
3. **Metaprogramming at boundaries** — registration / DSLs at tool edges; avoid dynamic dispatch in error paths and hot loops unless measured.
4. **Workspace rules** — validated tool schemas; loggable/replayable actions; **no hardcoded model names** (runtime config).

## 4. Pattern map (where code lives)

| Area | Patterns | Role |
|------|-----------|------|
| **Agent** | Facade, Template Method | Single entry; fixed loop with overridable hooks. |
| **Tools** | Factory, Command, Registry | Instantiate tools; optional command objects for audit. |
| **LLM** | Adapter, Proxy | Backends; cross-cutting logging/rate limits. |
| **Prompts** | Builder | Messages + tools + options. |
| **Streaming** | Observer | Fan-out from client `hooks`. |
| **Patches** | Strategy | Pluggable apply path. |
| **Conversation** | State | Explicit phases when control flow grows. |

### Target layout (illustrative)

A fuller **pattern-oriented** tree (with `bin/console`, `commands/`, `strategies/`, `states/`, etc.) and a **“this repo today”** note live in **reference.md** under *Recommended gem structure*. Migrate only when complexity justifies new directories.

```
ollama_agent/
├── exe/ollama_agent
├── lib/ollama_agent.rb
└── lib/ollama_agent/
    ├── agent.rb
    ├── cli.rb
    ├── prompt_builder.rb      # Builder (optional)
    ├── tool_registry.rb
    ├── tools/base.rb
    ├── tools/
    ├── llm/base_adapter.rb
    ├── llm/ollama_adapter.rb
    ├── llm/logging_proxy.rb
    ├── commands/tool_command.rb
    ├── observers/
    ├── strategies/
    └── states/
```

## 5. Creational patterns (summary)

- **Factory + registry** — Replace a growing `case` with `ToolRegistry.get(name)`; auto-register via `inherited` **or** explicit `tool_name` + hash (clearer than magic naming).
- **Builder** — `PromptBuilder` when message construction branches; skip until you have real optional composition.
- **Singleton** — Avoid as default for HTTP clients; use when you truly need one process-wide resource and tests can still stub.

## 6. Structural patterns (summary)

- **Adapter** — Common `chat(messages:, tools:, **options)` surface for Ollama vs future providers.
- **Proxy** — Wrap adapter for logging/metrics; keep thin.
- **Facade** — `Agent#run` — already the right shape.

## 7. Behavioral patterns (summary)

- **Command** — Wrap tool invocations when you need queues, structured logs, or replay; **undo** only with a real story (VCS/snapshots).
- **Observer** — Fan-out streaming tokens; compose with ollama-client `hooks`.
- **Strategy** — `PatchStrategy` if you need non-`patch` apply paths.
- **State** — When confirmation + tool rounds + idle become tangled.
- **Template Method** — Base agent class only if you have **multiple** agent variants sharing one loop.

## 8. Metaprogramming (judicious)

| Technique | Use when | Caution |
|-----------|----------|--------|
| **`inherited` + registry** | Many tools, stable naming | Keep in sync with **tool JSON schema**; consider explicit `tool_name`. |
| **Tool DSL** (`tool :name do …`) | Repetition dominates | Stack traces and IDE nav suffer; keep DSL thin. |
| **`send` for hooks** | Fixed event names | Prefer explicit methods for public API. |
| **`method_missing`** | Rare delegation | Not for core tool dispatch — use a Hash/registry. |
| **Plugin `extend`** | Third-party tools | Document load order and sandbox rules. |

## 9. When to avoid heavy metaprogramming

- Main agent loop and **error handling** — explicit flow wins.
- **Performance-sensitive** inner loops — measure before dynamic dispatch.
- **Public APIs** — stable, documented entry points over hidden DSL magic.

## 10. Summary

| Pattern | Benefit |
|---------|---------|
| Factory Method | Decouples tool creation from call sites. |
| Builder | Composes prompts/options without positional arg soup. |
| Singleton | Single shared resource (use sparingly for HTTP clients). |
| Adapter | Multiple LLM backends behind one shape. |
| Proxy | Cross-cutting concerns on the client. |
| Facade | Hides orchestration from CLI users. |
| Command | Tool calls as objects (log/replay/queue). |
| Observer | Decoupled streaming consumers. |
| Strategy | Swappable patch application. |
| State | Explicit conversation phases. |
| Template Method | Shared loop, varied steps. |
| Metaprogramming | Less boilerplate at **boundaries** only. |

**Start with straightforward code; refactor into patterns when pain appears.**

## 11. Full code examples

Runnable snippets (registry, `PromptBuilder`, adapters, proxy, command, observer, strategy, state, template-method skeleton, DSL sketch) live in **[reference.md](reference.md)**. Prefer copying from there and adapting to the real `ollama-client` API and this repo’s `SandboxedTools` / `tools_schema` constraints.

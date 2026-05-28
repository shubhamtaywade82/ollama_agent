# Session Runtime Integration Design

**Goal:** Wire the AI Runtime Shell so that `/model qwen3:32b` (and future runtime commands) mutate the active session via a clean dispatcher → session runtime → events pipeline. The command palette remains input-only; execution is a separate layer.

**Scope:** Additive — TuiRepl uses the new dispatcher. The text REPL's `ReplShared#handle_slash` case statement is untouched. Two paths coexist temporarily; full migration is a later phase.

---

## Architecture

```
User input
   │
   ▼
TuiSlashReader (input, ghost text, completion) ← unchanged
   │
   ▼ line submitted
TuiRepl#dispatch_slash
   │
   ├─► CommandDispatcher#dispatch(ast, session: session_runtime)
   │         │
   │         ▼
   │     Handler#call(ast:, session:)
   │         │
   │         ▼
   │     SessionRuntime#switch_model!(name)
   │         │
   │         ├─► @agent.assign_chat_model!(name)   ← existing mutation
   │         └─► RuntimeEvents#emit(:model_switched, ...)
   │                   │
   │                   ▼
   │             TuiRepl event handler → prints confirmation
   │
   └─► ReplShared#handle_slash(line)   ← fallback for unhandled commands
```

The command palette is never in this path. It parses input and provides suggestions; it does not dispatch commands.

---

## New Files

### `runtime_command_system/session/runtime.rb`

`SessionRuntime` wraps the agent and is the **only** mutation point for runtime state. All model/provider switches go through it so events always fire.

```ruby
module OllamaAgent
  module RuntimeCommandSystem
    module Session
      class Runtime
        attr_reader :events, :agent

        def initialize(agent:)
          @agent  = agent
          @events = Events.new
        end

        def active_model    = @agent.model
        def active_provider = @agent.provider_name

        def switch_model!(name, descriptor: nil)
          @agent.assign_chat_model!(name)
          @events.emit(:model_switched, model: name, descriptor: descriptor)
          name
        end

        def state
          { model: active_model, provider: active_provider }
        end

        def export_state
          state.merge(timestamp: Time.now.iso8601)
        end
      end
    end
  end
end
```

### `runtime_command_system/session/events.rb`

Minimal pub/sub — same pattern as `Streaming::Hooks` but scoped to runtime lifecycle events. Per-session instance (lives on `SessionRuntime`).

Events emitted: `:model_switched`, `:provider_switched` (future).

```ruby
module OllamaAgent
  module RuntimeCommandSystem
    module Session
      class Events
        def initialize
          @handlers = Hash.new { |h, k| h[k] = [] }
        end

        def on(event, &block)
          raise ArgumentError, "block required" unless block_given?
          @handlers[event.to_sym] << block
          self
        end

        def emit(event, payload = {})
          @handlers[event.to_sym].each do |h|
            h.call(payload)
          rescue StandardError
            nil
          end
        end

        def subscribed?(event)
          @handlers[event.to_sym].any?
        end
      end
    end
  end
end
```

### `runtime_command_system/dispatch/dispatcher.rb`

Routes command AST to registered handlers by command name. Returns `{ handled: false }` for unregistered commands so `TuiRepl` knows to fall back.

```ruby
module OllamaAgent
  module RuntimeCommandSystem
    module Dispatch
      class Dispatcher
        def initialize
          @handlers = {}
        end

        def register(command_name, handler)
          @handlers[normalize(command_name)] = handler
          self
        end

        def handles?(command_name)
          @handlers.key?(normalize(command_name))
        end

        def dispatch(ast, session:)
          handler = @handlers[normalize(ast.name)]
          return { handled: false } unless handler

          result = handler.call(ast: ast, session: session)
          (result || {}).merge(handled: true)
        end

        private

        def normalize(name) = name.to_s.delete_prefix("/").downcase
      end
    end
  end
end
```

### `runtime_command_system/dispatch/handlers/model_handler.rb`

Handles `/model [name]`. Resolves descriptor from `ModelRegistry`, delegates mutation to `SessionRuntime`. **No UI output** — the TUI listens to `RuntimeEvents` and prints confirmation.

```ruby
module OllamaAgent
  module RuntimeCommandSystem
    module Dispatch
      module Handlers
        class ModelHandler
          def call(ast:, session:)
            name = ast.arguments.first&.value.to_s.strip
            raise ArgumentError, "Missing model name" if name.empty?

            descriptor = Providers::ModelRegistry.find(name, agent: session.agent)
            session.switch_model!(name, descriptor: descriptor)
            { model: name, descriptor: descriptor }
          end
        end
      end
    end
  end
end
```

### `runtime_command_system/dispatch/handlers/provider_handler.rb`

Stub for `/provider`. Raises `NotImplementedError` with a helpful message. Architecture slot for future provider switching.

```ruby
module OllamaAgent
  module RuntimeCommandSystem
    module Dispatch
      module Handlers
        class ProviderHandler
          def call(ast:, session:)
            raise NotImplementedError,
                  "Provider switching requires session restart. Use: ollama_agent ask --provider #{ast.arguments.first&.value || '<name>'}"
          end
        end
      end
    end
  end
end
```

---

## TuiRepl Changes

### Startup wiring

```ruby
def initialize(agent:, tui:, ...)
  # existing...
  @session_runtime = build_session_runtime
  @dispatcher      = build_runtime_dispatcher
  wire_runtime_events
end

private

def build_session_runtime
  RuntimeCommandSystem::Session::Runtime.new(agent: @agent)
end

def build_runtime_dispatcher
  RuntimeCommandSystem::Dispatch::Dispatcher.new.tap do |d|
    d.register("model",    RuntimeCommandSystem::Dispatch::Handlers::ModelHandler.new)
    d.register("provider", RuntimeCommandSystem::Dispatch::Handlers::ProviderHandler.new)
  end
end

def wire_runtime_events
  @session_runtime.events.on(:model_switched) do |payload|
    on_model_switched(payload)
  end
end

def on_model_switched(payload)
  descriptor = payload[:descriptor]
  meta = descriptor ? "  #{descriptor.provider} • #{descriptor.context_size / 1000}k" : ""
  caps = descriptor&.capabilities&.-([:chat])&.map { |c| "[#{c}]" }&.join(" ")
  cap_str = caps && !caps.empty? ? "  #{caps}" : ""
  line = "  ✓ Model: \e[1;32m#{payload[:model]}\e[0m#{meta}#{cap_str}"
  @stdout.puts line
end
```

### dispatch_slash

```ruby
def dispatch_slash(line)
  ast = RuntimeCommandSystem::AST::Parser.parse(line)
  if ast && @dispatcher.handles?(ast.name)
    result = @dispatcher.dispatch(ast, session: @session_runtime)
    # confirmation printed by event handler; nothing else needed
  else
    handle_slash(line)
  end
rescue ArgumentError, NotImplementedError => e
  @tui.print_error("  #{e.message}")
rescue OllamaAgent::Error => e
  @tui.print_error("  Error: #{e.message}")
end
```

### Prompt badge

`ask_user_line` shows current model in the prompt:

```ruby
def read_user_line
  model_badge = "\e[2m[#{@session_runtime.active_model}]\e[0m "
  @tui.ask_user_line(
    completion_candidates: slash_completer_candidates,
    command_palette: runtime_command_palette,
    prompt_prefix: model_badge
  )
rescue Interrupt
  nil
end
```

`TUI#ask_user_line` accepts an optional `prompt_prefix:` kwarg prepended to the `❯ ` prompt.

---

## Error Handling

| Error                  | Handler      | TUI output                         |
|------------------------|-------------|-------------------------------------|
| Missing model name     | ArgumentError | `  Missing model name`             |
| Provider stub          | NotImplementedError | Message with restart hint   |
| Model not in registry  | Passes nil descriptor, switch still works (warns) | |
| Agent mutation error   | OllamaAgent::Error | `  Error: <message>`         |

Errors from handlers propagate to `TuiRepl#dispatch_slash` which catches them and prints via `@tui.print_error`.

---

## Testing Plan

| File                                     | What to test                                              |
|------------------------------------------|-----------------------------------------------------------|
| `spec/.../session/runtime_spec.rb`       | switch_model! mutates agent + emits event; export_state   |
| `spec/.../session/events_spec.rb`        | on/emit/swallow errors                                    |
| `spec/.../dispatch/dispatcher_spec.rb`   | register/handles?/dispatch routes correctly               |
| `spec/.../dispatch/handlers/model_handler_spec.rb` | delegates to session, raises on missing name  |
| `spec/.../cli/tui_repl_spec.rb` (new)   | dispatch_slash routes to dispatcher; falls back to handle_slash |

---

## What This Does NOT Include

- Provider switching (stub only — requires session restart)
- Fuzzy model name matching
- Async model loading
- Capability routing or adaptive orchestration
- Status line with token counts (TUI status bar is prompt badge only)
- Full replacement of `ReplShared#handle_slash` (later phase)

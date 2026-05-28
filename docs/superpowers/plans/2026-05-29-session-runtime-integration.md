# Session Runtime Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `/model <name>` through a clean CommandDispatcher → SessionRuntime → RuntimeEvents pipeline so model switching mutates live session state and fires events the TUI consumes for confirmation display and prompt badge.

**Architecture:** Additive layer — TuiRepl gets a CommandDispatcher and SessionRuntime at startup; `dispatch_slash` tries the dispatcher first and falls back to the existing `ReplShared#handle_slash` for everything else. The command palette remains input-only. All new code lives under `runtime_command_system/session/` and `runtime_command_system/dispatch/`.

**Tech Stack:** Ruby, RSpec, TTY toolkit (existing), `OllamaAgent::Providers::ModelRegistry` (existing), `OllamaAgent::Agent#assign_chat_model!` (existing)

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `lib/ollama_agent/runtime_command_system/session/events.rb` | Lightweight pub/sub for runtime lifecycle events |
| Create | `lib/ollama_agent/runtime_command_system/session/runtime.rb` | Single mutation point for model/provider state; wraps Agent |
| Create | `lib/ollama_agent/runtime_command_system/dispatch/dispatcher.rb` | Routes command AST to registered handlers |
| Create | `lib/ollama_agent/runtime_command_system/dispatch/handlers/model_handler.rb` | Handles `/model <name>` — resolves descriptor, calls session.switch_model! |
| Create | `lib/ollama_agent/runtime_command_system/dispatch/handlers/provider_handler.rb` | Stub for `/provider` — raises NotImplementedError with restart hint |
| Create | `spec/ollama_agent/runtime_command_system/session/events_spec.rb` | |
| Create | `spec/ollama_agent/runtime_command_system/session/runtime_spec.rb` | |
| Create | `spec/ollama_agent/runtime_command_system/dispatch/dispatcher_spec.rb` | |
| Create | `spec/ollama_agent/runtime_command_system/dispatch/handlers/model_handler_spec.rb` | |
| Modify | `lib/ollama_agent/tui.rb:98-107` | Add `prompt_prefix:` kwarg to `ask_user_line` |
| Modify | `lib/ollama_agent/cli/tui_repl.rb` | Wire SessionRuntime + Dispatcher; update dispatch_slash and read_user_line |

**Key existing methods:**
- `OllamaAgent::Agent#assign_chat_model!(name)` — mutates `@model`, returns name string
- `OllamaAgent::Providers::ModelRegistry.find(name, agent:)` — returns `ModelDescriptor` or nil
- `OllamaAgent::RuntimeCommandSystem::AST::Parser.parse(text)` — returns `CommandNode` or nil
- `CommandNode#argument_context?` — true if raw input contains a space (arg present)
- `CommandNode#arguments` — Array of `ArgumentNode`; `ArgumentNode#value` — String token

---

## Task 1: RuntimeEvents

**Files:**
- Create: `lib/ollama_agent/runtime_command_system/session/events.rb`
- Create: `spec/ollama_agent/runtime_command_system/session/events_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/ollama_agent/runtime_command_system/session/events_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/runtime_command_system/session/events"

RSpec.describe OllamaAgent::RuntimeCommandSystem::Session::Events do
  subject(:events) { described_class.new }

  it "calls registered handler when event emitted" do
    received = nil
    events.on(:model_switched) { |p| received = p }
    events.emit(:model_switched, model: "qwen3:32b")
    expect(received).to eq(model: "qwen3:32b")
  end

  it "swallows errors raised inside handlers" do
    events.on(:model_switched) { raise "boom" }
    expect { events.emit(:model_switched, {}) }.not_to raise_error
  end

  it "subscribed? returns false with no handlers" do
    expect(events.subscribed?(:model_switched)).to be false
  end

  it "subscribed? returns true after registering a handler" do
    events.on(:model_switched) { nil }
    expect(events.subscribed?(:model_switched)).to be true
  end

  it "requires a block when registering" do
    expect { events.on(:model_switched) }.to raise_error(ArgumentError)
  end
end
```

- [ ] **Step 2: Run to confirm failures**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/session/events_spec.rb -f doc
```

Expected: FAIL — file `session/events.rb` does not exist.

- [ ] **Step 3: Create the events file**

```ruby
# lib/ollama_agent/runtime_command_system/session/events.rb
# frozen_string_literal: true

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
          @handlers[event.to_sym].each do |handler|
            handler.call(payload)
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

- [ ] **Step 4: Run to confirm pass**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/session/events_spec.rb -f doc
```

Expected: 5 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/ollama_agent/runtime_command_system/session/events.rb \
        spec/ollama_agent/runtime_command_system/session/events_spec.rb
git commit -m "feat: add RuntimeCommandSystem::Session::Events lightweight pub/sub"
```

---

## Task 2: SessionRuntime

**Files:**
- Create: `lib/ollama_agent/runtime_command_system/session/runtime.rb`
- Create: `spec/ollama_agent/runtime_command_system/session/runtime_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/ollama_agent/runtime_command_system/session/runtime_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/runtime_command_system/session/events"
require "ollama_agent/runtime_command_system/session/runtime"

RSpec.describe OllamaAgent::RuntimeCommandSystem::Session::Runtime do
  let(:agent) do
    instance_double(OllamaAgent::Agent, model: "qwen3:32b", provider_name: "local")
  end

  subject(:runtime) { described_class.new(agent: agent) }

  it "delegates active_model to agent" do
    expect(runtime.active_model).to eq("qwen3:32b")
  end

  it "delegates active_provider to agent" do
    expect(runtime.active_provider).to eq("local")
  end

  it "exposes the agent" do
    expect(runtime.agent).to be(agent)
  end

  it "exposes an Events instance" do
    expect(runtime.events).to be_a(OllamaAgent::RuntimeCommandSystem::Session::Events)
  end

  describe "#switch_model!" do
    before do
      allow(agent).to receive(:assign_chat_model!).with("deepseek-r1").and_return("deepseek-r1")
    end

    it "calls agent.assign_chat_model!" do
      runtime.switch_model!("deepseek-r1")
      expect(agent).to have_received(:assign_chat_model!).with("deepseek-r1")
    end

    it "emits :model_switched event with model name" do
      received = nil
      runtime.events.on(:model_switched) { |p| received = p }
      runtime.switch_model!("deepseek-r1")
      expect(received[:model]).to eq("deepseek-r1")
    end

    it "passes descriptor in event payload when provided" do
      descriptor = double("descriptor")
      received = nil
      runtime.events.on(:model_switched) { |p| received = p }
      runtime.switch_model!("deepseek-r1", descriptor: descriptor)
      expect(received[:descriptor]).to be(descriptor)
    end

    it "returns the model name" do
      expect(runtime.switch_model!("deepseek-r1")).to eq("deepseek-r1")
    end
  end

  describe "#state" do
    it "returns a hash with model and provider" do
      expect(runtime.state).to eq(model: "qwen3:32b", provider: "local")
    end
  end

  describe "#export_state" do
    it "includes timestamp key" do
      expect(runtime.export_state).to include(:timestamp)
    end

    it "includes model and provider" do
      exported = runtime.export_state
      expect(exported[:model]).to eq("qwen3:32b")
      expect(exported[:provider]).to eq("local")
    end
  end
end
```

- [ ] **Step 2: Run to confirm failures**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/session/runtime_spec.rb -f doc
```

Expected: FAIL — file does not exist.

- [ ] **Step 3: Create SessionRuntime**

```ruby
# lib/ollama_agent/runtime_command_system/session/runtime.rb
# frozen_string_literal: true

require_relative "events"

module OllamaAgent
  module RuntimeCommandSystem
    module Session
      class Runtime
        attr_reader :events, :agent

        def initialize(agent:)
          @agent  = agent
          @events = Events.new
        end

        def active_model
          @agent.model
        end

        def active_provider
          @agent.provider_name
        end

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

- [ ] **Step 4: Run to confirm pass**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/session/runtime_spec.rb -f doc
```

Expected: 10 examples, 0 failures.

- [ ] **Step 5: Run broader suite for regression check**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/ -f progress
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/ollama_agent/runtime_command_system/session/runtime.rb \
        spec/ollama_agent/runtime_command_system/session/runtime_spec.rb
git commit -m "feat: add SessionRuntime — single mutation point for model/provider state"
```

---

## Task 3: CommandDispatcher

**Files:**
- Create: `lib/ollama_agent/runtime_command_system/dispatch/dispatcher.rb`
- Create: `spec/ollama_agent/runtime_command_system/dispatch/dispatcher_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/ollama_agent/runtime_command_system/dispatch/dispatcher_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/runtime_command_system/ast"
require "ollama_agent/runtime_command_system/dispatch/dispatcher"

RSpec.describe OllamaAgent::RuntimeCommandSystem::Dispatch::Dispatcher do
  subject(:dispatcher) { described_class.new }

  let(:handler) { instance_double("Handler") }
  let(:session) { double("session") }

  before do
    dispatcher.register("model", handler)
  end

  describe "#handles?" do
    it "returns true for registered command (no slash)" do
      expect(dispatcher.handles?("model")).to be true
    end

    it "returns true for registered command (with slash)" do
      expect(dispatcher.handles?("/model")).to be true
    end

    it "returns false for unregistered command" do
      expect(dispatcher.handles?("help")).to be false
    end
  end

  describe "#dispatch" do
    it "routes to the registered handler and merges handled: true" do
      allow(handler).to receive(:call).with(
        ast: anything, session: session
      ).and_return({ model: "qwen3:32b" })

      ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model qwen3:32b")
      result = dispatcher.dispatch(ast, session: session)

      expect(result[:handled]).to be true
      expect(result[:model]).to eq("qwen3:32b")
    end

    it "returns handled: false for unregistered command" do
      ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/help")
      result = dispatcher.dispatch(ast, session: session)
      expect(result[:handled]).to be false
    end

    it "merges handled: true even when handler returns nil" do
      allow(handler).to receive(:call).and_return(nil)
      ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model qwen3:32b")
      result = dispatcher.dispatch(ast, session: session)
      expect(result[:handled]).to be true
    end
  end
end
```

- [ ] **Step 2: Run to confirm failures**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/dispatch/dispatcher_spec.rb -f doc
```

Expected: FAIL — file does not exist.

- [ ] **Step 3: Create Dispatcher**

```ruby
# lib/ollama_agent/runtime_command_system/dispatch/dispatcher.rb
# frozen_string_literal: true

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

        def normalize(name)
          name.to_s.delete_prefix("/").downcase
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run to confirm pass**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/dispatch/dispatcher_spec.rb -f doc
```

Expected: 6 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/ollama_agent/runtime_command_system/dispatch/dispatcher.rb \
        spec/ollama_agent/runtime_command_system/dispatch/dispatcher_spec.rb
git commit -m "feat: add CommandDispatcher — routes command AST to registered handlers"
```

---

## Task 4: ModelHandler + ProviderHandler

**Files:**
- Create: `lib/ollama_agent/runtime_command_system/dispatch/handlers/model_handler.rb`
- Create: `lib/ollama_agent/runtime_command_system/dispatch/handlers/provider_handler.rb`
- Create: `spec/ollama_agent/runtime_command_system/dispatch/handlers/model_handler_spec.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/ollama_agent/runtime_command_system/dispatch/handlers/model_handler_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/runtime_command_system/ast"
require "ollama_agent/runtime_command_system/dispatch/handlers/model_handler"

RSpec.describe OllamaAgent::RuntimeCommandSystem::Dispatch::Handlers::ModelHandler do
  subject(:handler) { described_class.new }

  let(:agent) { instance_double(OllamaAgent::Agent) }
  let(:session) do
    instance_double(
      OllamaAgent::RuntimeCommandSystem::Session::Runtime,
      agent: agent
    )
  end

  before do
    allow(OllamaAgent::Providers::ModelRegistry).to receive(:find).and_return(nil)
    allow(session).to receive(:switch_model!)
  end

  it "calls session.switch_model! with the model name" do
    ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model qwen3:32b")
    handler.call(ast: ast, session: session)
    expect(session).to have_received(:switch_model!).with("qwen3:32b", descriptor: nil)
  end

  it "returns a hash with the model name" do
    ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model qwen3:32b")
    result = handler.call(ast: ast, session: session)
    expect(result[:model]).to eq("qwen3:32b")
  end

  it "raises ArgumentError when no model name given (bare /model)" do
    ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model")
    expect { handler.call(ast: ast, session: session) }.to raise_error(ArgumentError, /Missing model name/)
  end

  it "raises ArgumentError when argument is only whitespace" do
    ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model ")
    expect { handler.call(ast: ast, session: session) }.to raise_error(ArgumentError, /Missing model name/)
  end

  it "passes found descriptor to switch_model!" do
    descriptor = instance_double(OllamaAgent::Providers::ModelDescriptor, name: "qwen3:32b")
    allow(OllamaAgent::Providers::ModelRegistry).to receive(:find)
      .with("qwen3:32b", agent: agent)
      .and_return(descriptor)

    ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model qwen3:32b")
    handler.call(ast: ast, session: session)
    expect(session).to have_received(:switch_model!).with("qwen3:32b", descriptor: descriptor)
  end

  it "passes nil descriptor when model not found in registry" do
    allow(OllamaAgent::Providers::ModelRegistry).to receive(:find).and_return(nil)
    ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model unknown-model")
    handler.call(ast: ast, session: session)
    expect(session).to have_received(:switch_model!).with("unknown-model", descriptor: nil)
  end
end
```

- [ ] **Step 2: Run to confirm failures**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/dispatch/handlers/model_handler_spec.rb -f doc
```

Expected: FAIL — file does not exist.

- [ ] **Step 3: Create ModelHandler**

```ruby
# lib/ollama_agent/runtime_command_system/dispatch/handlers/model_handler.rb
# frozen_string_literal: true

require_relative "../../session/runtime"

module OllamaAgent
  module RuntimeCommandSystem
    module Dispatch
      module Handlers
        class ModelHandler
          def call(ast:, session:)
            name = ast.arguments.first&.value.to_s.strip
            raise ArgumentError, "Missing model name — usage: /model <name>" if name.empty?

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

- [ ] **Step 4: Create ProviderHandler**

```ruby
# lib/ollama_agent/runtime_command_system/dispatch/handlers/provider_handler.rb
# frozen_string_literal: true

module OllamaAgent
  module RuntimeCommandSystem
    module Dispatch
      module Handlers
        class ProviderHandler
          def call(ast:, session:)
            provider = ast.arguments.first&.value.to_s.strip
            hint = provider.empty? ? "<name>" : provider
            raise NotImplementedError,
                  "Provider switching requires session restart. " \
                  "Use: ollama_agent ask --provider #{hint}"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: Run tests to confirm pass**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/dispatch/handlers/model_handler_spec.rb -f doc
```

Expected: 6 examples, 0 failures.

- [ ] **Step 6: Run full runtime_command_system suite**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/ -f progress
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add lib/ollama_agent/runtime_command_system/dispatch/handlers/model_handler.rb \
        lib/ollama_agent/runtime_command_system/dispatch/handlers/provider_handler.rb \
        spec/ollama_agent/runtime_command_system/dispatch/handlers/model_handler_spec.rb
git commit -m "feat: add ModelHandler and ProviderHandler for RuntimeDispatch"
```

---

## Task 5: TUI#ask_user_line gets prompt_prefix kwarg

**Files:**
- Modify: `lib/ollama_agent/tui.rb:98-107`
- Modify: `spec/ollama_agent/tui_spec.rb` (add one test)

The current `ask_user_line` signature:

```ruby
def ask_user_line(completion_candidates: [], command_palette: nil)
  prompt = @pastel.green.bold("❯ ")
  ...
```

Needs `prompt_prefix: nil` so `TuiRepl` can prepend a dimmed model badge.

- [ ] **Step 1: Write the failing test**

Read `spec/ollama_agent/tui_spec.rb` first to understand existing test structure. Then add:

```ruby
describe "#ask_user_line with prompt_prefix" do
  it "includes prompt_prefix in the string passed to read_line" do
    captured_prompt = nil
    slash_reader = instance_double(OllamaAgent::TuiSlashReader)
    allow(slash_reader).to receive(:completion_candidates=)
    allow(slash_reader).to receive(:command_palette=)
    allow(slash_reader).to receive(:read_line) { |prompt| captured_prompt = prompt; "" }

    tui = described_class.new(stdout: StringIO.new)
    tui.instance_variable_set(:@slash_reader, slash_reader)
    tui.ask_user_line(prompt_prefix: "[qwen3:32b] ")

    expect(captured_prompt).to include("[qwen3:32b]")
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/ollama_agent/tui_spec.rb -f doc
```

Expected: FAIL — `ask_user_line` doesn't accept `prompt_prefix:` kwarg yet.

- [ ] **Step 3: Add prompt_prefix to ask_user_line**

In `lib/ollama_agent/tui.rb`, change lines 98-107:

```ruby
# Before:
def ask_user_line(completion_candidates: [], command_palette: nil)
  prompt = @pastel.green.bold("❯ ")
  @slash_reader.completion_candidates = Array(completion_candidates).uniq.sort
  @slash_reader.command_palette = command_palette
  line = @slash_reader.read_line(prompt).to_s
  save_history
  line
rescue TTY::Reader::InputInterrupt
  nil
end

# After:
def ask_user_line(completion_candidates: [], command_palette: nil, prompt_prefix: nil)
  prefix = prompt_prefix.to_s
  prompt = "#{prefix}#{@pastel.green.bold("❯ ")}"
  @slash_reader.completion_candidates = Array(completion_candidates).uniq.sort
  @slash_reader.command_palette = command_palette
  line = @slash_reader.read_line(prompt).to_s
  save_history
  line
rescue TTY::Reader::InputInterrupt
  nil
end
```

- [ ] **Step 4: Run test to confirm pass**

```bash
bundle exec rspec spec/ollama_agent/tui_spec.rb -f doc
```

Expected: all pass including new test.

- [ ] **Step 5: Commit**

```bash
git add lib/ollama_agent/tui.rb spec/ollama_agent/tui_spec.rb
git commit -m "feat: add prompt_prefix kwarg to TUI#ask_user_line for model badge"
```

---

## Task 6: TuiRepl wiring

**Files:**
- Modify: `lib/ollama_agent/cli/tui_repl.rb`
- Create or modify: `spec/ollama_agent/cli/tui_repl_dispatch_spec.rb`

Wire `SessionRuntime`, `CommandDispatcher`, event handler, `dispatch_slash` routing, and prompt badge.

- [ ] **Step 1: Write failing tests**

Create `spec/ollama_agent/cli/tui_repl_dispatch_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/cli/tui_repl"

RSpec.describe OllamaAgent::CLI::TuiRepl do
  let(:stdout) { StringIO.new }
  let(:agent) do
    instance_double(
      OllamaAgent::Agent,
      model: "qwen3:32b",
      provider_name: "local",
      instance_variable_get: nil
    )
  end
  let(:tui) { instance_double(OllamaAgent::TUI, log: nil) }

  before do
    allow(OllamaAgent::Plugins::Registry).to receive(:all_command_handlers).and_return([])
    allow(OllamaAgent::Providers::ModelRegistry).to receive(:find).and_return(nil)
    allow(agent).to receive(:assign_chat_model!).and_return("deepseek-r1")
  end

  subject(:repl) { described_class.new(agent: agent, tui: tui, stdout: stdout) }

  describe "#dispatch_slash routing" do
    it "routes /model <name> through the RuntimeDispatcher" do
      repl.send(:dispatch_slash, "/model deepseek-r1")
      expect(agent).to have_received(:assign_chat_model!).with("deepseek-r1")
    end

    it "falls back to handle_slash for /help" do
      expect(repl).to receive(:handle_slash).with("/help")
      repl.send(:dispatch_slash, "/help")
    end

    it "falls back to handle_slash for bare /model (no arg)" do
      expect(repl).to receive(:handle_slash).with("/model")
      repl.send(:dispatch_slash, "/model")
    end

    it "falls back to handle_slash for /model list" do
      expect(repl).to receive(:handle_slash).with("/model list")
      repl.send(:dispatch_slash, "/model list")
    end

    it "prints error via tui when model name missing after space" do
      allow(tui).to receive(:print_error)
      repl.send(:dispatch_slash, "/model ")
      expect(tui).to have_received(:print_error).with(match(/Missing model name/))
    end
  end

  describe "prompt badge" do
    it "session_runtime reflects current model" do
      expect(repl.send(:session_runtime).active_model).to eq("qwen3:32b")
    end
  end
end
```

- [ ] **Step 2: Run to confirm failures**

```bash
bundle exec rspec spec/ollama_agent/cli/tui_repl_dispatch_spec.rb -f doc
```

Expected: multiple failures — `session_runtime`, `dispatch_slash` routing, `build_runtime_dispatcher` don't exist yet.

- [ ] **Step 3: Add requires to tui_repl.rb**

At the top of `lib/ollama_agent/cli/tui_repl.rb`, after existing requires, add:

```ruby
require_relative "../runtime_command_system/session/runtime"
require_relative "../runtime_command_system/dispatch/dispatcher"
require_relative "../runtime_command_system/dispatch/handlers/model_handler"
require_relative "../runtime_command_system/dispatch/handlers/provider_handler"
```

- [ ] **Step 4: Wire initialize**

In `TuiRepl#initialize`, after all existing assignments, add:

```ruby
@session_runtime = build_session_runtime
@dispatcher      = build_runtime_dispatcher
wire_runtime_events
```

- [ ] **Step 5: Add private builder methods**

Add to the private section of `TuiRepl`:

```ruby
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
  @session_runtime.events.on(:model_switched) { |payload| on_model_switched(payload) }
end

def on_model_switched(payload)
  descriptor = payload[:descriptor]
  meta = descriptor ? "  #{descriptor.provider} • #{descriptor.context_size / 1000}k" : ""
  caps = descriptor&.capabilities&.-([:chat])&.map { |c| "[#{c}]" }&.join(" ")
  cap_str = caps && !caps.empty? ? "  #{caps}" : ""
  @stdout.puts "  ✓ Model: \e[1;32m#{payload[:model]}\e[0m#{meta}#{cap_str}"
end

def session_runtime
  @session_runtime
end

def runtime_dispatchable?(ast)
  return false unless ast.argument_context?

  arg = ast.arguments.first&.value.to_s.strip
  return false if arg.empty? || arg.casecmp("list").zero?

  true
end
```

- [ ] **Step 6: Replace dispatch_slash**

Find and replace the existing `dispatch_slash` method:

```ruby
# Before:
def dispatch_slash(line)
  if line == "/status"
    show_context_dashboard
    return
  end

  handle_slash(line)
end

# After:
def dispatch_slash(line)
  return show_context_dashboard if line == "/status"

  ast = RuntimeCommandSystem::AST::Parser.parse(line)
  if ast && @dispatcher.handles?(ast.name) && runtime_dispatchable?(ast)
    @dispatcher.dispatch(ast, session: @session_runtime)
  else
    handle_slash(line)
  end
rescue ArgumentError, NotImplementedError => e
  @tui.print_error("  #{e.message}")
rescue OllamaAgent::Error => e
  @tui.print_error("  Error: #{e.message}")
end
```

- [ ] **Step 7: Add model badge to read_user_line**

Find and replace `read_user_line`:

```ruby
# Before:
def read_user_line
  @tui.ask_user_line(completion_candidates: slash_completer_candidates, command_palette: runtime_command_palette)
rescue Interrupt
  nil
end

# After:
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

- [ ] **Step 8: Run tests**

```bash
bundle exec rspec spec/ollama_agent/cli/tui_repl_dispatch_spec.rb -f doc
```

Expected: all pass.

- [ ] **Step 9: Run full suite**

```bash
bundle exec rspec --format progress 2>&1 | tail -10
```

Expected: all examples pass, 0 failures.

- [ ] **Step 10: Commit**

```bash
git add lib/ollama_agent/cli/tui_repl.rb \
        spec/ollama_agent/cli/tui_repl_dispatch_spec.rb
git commit -m "feat: wire SessionRuntime + CommandDispatcher into TuiRepl — /model now mutates live session"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|-----------------|------|
| `SessionRuntime#switch_model!` mutates agent + emits event | Task 2 |
| `RuntimeEvents` pub/sub with error swallowing | Task 1 |
| `CommandDispatcher` registers handlers, routes AST | Task 3 |
| `ModelHandler` resolves descriptor, delegates to session | Task 4 |
| `ProviderHandler` raises `NotImplementedError` with restart hint | Task 4 |
| `TUI#ask_user_line` accepts `prompt_prefix:` kwarg | Task 5 |
| `TuiRepl` wires session + dispatcher at startup | Task 6 |
| `dispatch_slash` routes to dispatcher, falls back to `handle_slash` | Task 6 |
| `/model list` and bare `/model` fall through to `handle_slash` | Task 6 (runtime_dispatchable?) |
| Model badge `[qwen3:32b]` in prompt | Task 6 (read_user_line) |
| `export_state` returns serializable hash with timestamp | Task 2 |
| Error handling: ArgumentError/NotImplementedError → `tui.print_error` | Task 6 |

**No gaps found.**

**Placeholder scan:** No TBD, no "implement later", all code blocks complete.

**Type consistency:**
- `Session::Runtime` exposed as `@session_runtime` — consistent across Task 2 and Task 6
- `Dispatch::Dispatcher#dispatch(ast, session:)` — matches Task 3 interface and Task 6 call site
- `ModelHandler#call(ast:, session:)` — session receives `switch_model!(name, descriptor:)` — matches Task 2 signature
- `on_model_switched` reads `payload[:model]` and `payload[:descriptor]` — matches Task 2 emit payload
- `runtime_dispatchable?` guards `dispatch_slash` — guards bare `/model` and `/model list` fallthrough

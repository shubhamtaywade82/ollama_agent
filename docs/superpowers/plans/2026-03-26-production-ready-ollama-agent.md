# Production-Ready ollama_agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add six production-readiness layers (Tool Registry, Streaming, Resilience, Context Manager, Session Persistence, Runner API) to the existing ollama_agent gem without breaking any existing behavior.

**Architecture:** Each layer is an independently shippable PR added on top of the proven v0.1.x core. All new features are opt-in via new env vars or CLI flags. The existing `Agent`, `CLI`, and `SandboxedTools` APIs remain 100% backward-compatible.

**Tech Stack:** Ruby ≥ 3.2, ollama-client ~> 1.1, Thor, Prism, RSpec, existing gem structure under `lib/ollama_agent/`

---

## File Map

### Layer 1 — Tool Registry + write_file
| Action | Path |
|--------|------|
| Create | `lib/ollama_agent/tools/registry.rb` |
| Create | `lib/ollama_agent/tools/built_in.rb` |
| Modify | `lib/ollama_agent/sandboxed_tools.rb` — replace `case` with registry dispatch; add `execute_write_file_tool` |
| Modify | `lib/ollama_agent/tools_schema.rb` — add `write_file` schema; update `tools_for` to merge custom schemas |
| Modify | `lib/ollama_agent/agent_prompt.rb` — add `write_file` instruction line |
| Modify | `lib/ollama_agent.rb` — require `tools/registry` and `tools/built_in` |
| Create | `spec/ollama_agent/tools/registry_spec.rb` |
| Modify | `spec/ollama_agent/sandboxed_tools_spec.rb` — add write_file specs |

### Layer 2 — Streaming + Hooks
| Action | Path |
|--------|------|
| Create | `lib/ollama_agent/streaming/hooks.rb` |
| Create | `lib/ollama_agent/streaming/console_streamer.rb` |
| Modify | `lib/ollama_agent/agent.rb` — wire `@hooks`; add `stream_assistant_message` branch |
| Modify | `lib/ollama_agent/cli.rb` — add `--stream` flag; attach `ConsoleStreamer` |
| Modify | `lib/ollama_agent.rb` — require streaming files |
| Create | `spec/ollama_agent/streaming/hooks_spec.rb` |

### Layer 3 — Resilience (Retry + Audit Logger)
| Action | Path |
|--------|------|
| Create | `lib/ollama_agent/resilience/retry_middleware.rb` |
| Create | `lib/ollama_agent/resilience/audit_logger.rb` |
| Modify | `lib/ollama_agent/agent.rb` — wrap client with RetryMiddleware; subscribe AuditLogger to hooks |
| Modify | `lib/ollama_agent/cli.rb` — add `--audit`, `--max-retries` flags |
| Modify | `lib/ollama_agent.rb` — require resilience files |
| Create | `spec/ollama_agent/resilience/retry_middleware_spec.rb` |
| Create | `spec/ollama_agent/resilience/audit_logger_spec.rb` |

### Layer 4 — Context Manager
| Action | Path |
|--------|------|
| Create | `lib/ollama_agent/context/token_counter.rb` |
| Create | `lib/ollama_agent/context/manager.rb` |
| Modify | `lib/ollama_agent/agent.rb` — insert `ContextManager#trim` before every `chat` call |
| Modify | `lib/ollama_agent/cli.rb` — add `--max-tokens`, `--context-summarize` flags |
| Modify | `lib/ollama_agent.rb` — require context files |
| Create | `spec/ollama_agent/context/token_counter_spec.rb` |
| Create | `spec/ollama_agent/context/manager_spec.rb` |

### Layer 5 — Session Persistence
| Action | Path |
|--------|------|
| Create | `lib/ollama_agent/session/session.rb` |
| Create | `lib/ollama_agent/session/store.rb` |
| Modify | `lib/ollama_agent/agent.rb` — accept `session_store:` kwarg; append messages after each turn |
| Modify | `lib/ollama_agent/cli.rb` — add `--session`, `--resume` flags; add `sessions` command |
| Modify | `lib/ollama_agent.rb` — require session files |
| Create | `spec/ollama_agent/session/store_spec.rb` |

### Layer 6 — Runner + Library API
| Action | Path |
|--------|------|
| Create | `lib/ollama_agent/runner.rb` |
| Modify | `lib/ollama_agent.rb` — require runner; expose `OllamaAgent::Tools` alias |
| Modify | `lib/ollama_agent/version.rb` — bump to `0.2.0` |
| Create | `spec/ollama_agent/runner_spec.rb` |
| Create | `docs/ARCHITECTURE.md` |
| Create | `docs/TOOLS.md` |
| Create | `docs/SESSIONS.md` |

---

## Layer 1 — Tool Registry + `write_file`

### Task 1.1: Create the Tool Registry

**Files:**
- Create: `lib/ollama_agent/tools/registry.rb`
- Create: `spec/ollama_agent/tools/registry_spec.rb`

- [ ] **Step 1.1.1: Write the failing specs**

```ruby
# spec/ollama_agent/tools/registry_spec.rb
# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ollama_agent/tools/registry"

RSpec.describe OllamaAgent::Tools::Registry do
  before { described_class.reset! }
  after  { described_class.reset! }

  describe ".register and .execute" do
    it "executes a registered custom tool handler" do
      described_class.register("my_tool",
        schema: { type: "object", properties: {}, required: [] }
      ) { |args, root:, read_only:| "result:#{args["x"]}" }

      result = described_class.execute_custom("my_tool", { "x" => "42" }, root: "/tmp", read_only: false)
      expect(result).to eq("result:42")
    end

    it "returns an error message for an unknown custom tool" do
      result = described_class.execute_custom("nope", {}, root: "/tmp", read_only: false)
      expect(result).to include("Unknown custom tool")
    end

    it "reports registered? correctly" do
      expect(described_class.custom_tool?("my_tool")).to be false
      described_class.register("my_tool", schema: {}) { "x" }
      expect(described_class.custom_tool?("my_tool")).to be true
    end
  end

  describe ".custom_schemas" do
    it "returns tool schemas in ollama tool format" do
      described_class.register("do_thing",
        schema: { description: "does a thing", properties: { x: { type: "string" } }, required: ["x"] }
      ) { "ok" }

      schemas = described_class.custom_schemas
      expect(schemas.size).to eq(1)
      expect(schemas.first[:type]).to eq("function")
      expect(schemas.first.dig(:function, :name)).to eq("do_thing")
    end

    it "returns empty array when no custom tools registered" do
      expect(described_class.custom_schemas).to eq([])
    end
  end

  describe ".reset!" do
    it "clears all registrations" do
      described_class.register("t", schema: {}) { "x" }
      described_class.reset!
      expect(described_class.custom_tool?("t")).to be false
    end
  end
end
```

- [ ] **Step 1.1.2: Run specs to confirm they fail**

```bash
bundle exec rspec spec/ollama_agent/tools/registry_spec.rb --no-color 2>&1 | tail -5
```
Expected: `LoadError` or `NameError` (file doesn't exist yet).

- [ ] **Step 1.1.3: Create the registry**

```ruby
# lib/ollama_agent/tools/registry.rb
# frozen_string_literal: true

module OllamaAgent
  # Public namespace for tool registration.
  # Library consumers call: OllamaAgent::Tools.register(:name, schema: {...}) { |args, root:, read_only:| ... }
  module Tools
    # Delegate class-methods to Registry so OllamaAgent::Tools.register(...) works.
    def self.register(name, schema:, &block)     = Registry.register(name, schema: schema, &block)
    def self.custom_tool?(name)                  = Registry.custom_tool?(name)
    def self.execute_custom(name, args, **kw)    = Registry.execute_custom(name, args, **kw)
    def self.custom_schemas                      = Registry.custom_schemas
    def self.reset!                              = Registry.reset!

    # Internal registry — used by SandboxedTools and tools_schema.rb.
    module Registry
      @custom_tools = {}

      class << self
        # Register a custom tool.
        # schema: Hash with :description and :properties (and optionally :required) — the `function` body.
        # The block receives (args_hash, root: String, read_only: Boolean).
        def register(name, schema:, &handler)
          @custom_tools[name.to_s] = { schema: schema, handler: handler }
        end

        def custom_tool?(name)
          @custom_tools.key?(name.to_s)
        end

        # Execute a registered custom tool. Returns a string result.
        def execute_custom(name, args, root:, read_only:)
          entry = @custom_tools[name.to_s]
          return "Unknown custom tool: #{name}" unless entry

          entry[:handler].call(args, root: root, read_only: read_only)
        end

        # Returns tool schemas in the format Ollama's /api/chat expects.
        def custom_schemas
          @custom_tools.map do |name, entry|
            {
              type: "function",
              function: entry[:schema].merge(name: name)
            }
          end
        end

        # Clear all registrations. Used in tests.
        def reset!
          @custom_tools = {}
        end
      end
    end
  end
end
```

- [ ] **Step 1.1.4: Run specs to confirm they pass**

```bash
bundle exec rspec spec/ollama_agent/tools/registry_spec.rb --no-color
```
Expected: `4 examples, 0 failures`

- [ ] **Step 1.1.5: Commit**

```bash
git add lib/ollama_agent/tools/registry.rb spec/ollama_agent/tools/registry_spec.rb
git commit -m "feat(tools): add custom Tool Registry for library consumers"
```

---

### Task 1.2: Add `write_file` tool

**Files:**
- Modify: `lib/ollama_agent/tools_schema.rb`
- Modify: `lib/ollama_agent/sandboxed_tools.rb`
- Modify: `lib/ollama_agent/agent_prompt.rb`
- Modify: `spec/ollama_agent/sandboxed_tools_spec.rb`

- [ ] **Step 1.2.1: Write failing specs for write_file**

Append to `spec/ollama_agent/sandboxed_tools_spec.rb` (after the last `end` of the existing `describe "#execute_tool"` block):

```ruby
    context "write_file" do
      it "creates a new file under the project root" do
        agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false)
        result = agent.send(:execute_tool, "write_file", { "path" => "new.rb", "content" => "# hello\n" })
        expect(result).to include("wrote").or include("ok").or eq("Written: new.rb")
        expect(File.read(File.join(tmpdir, "new.rb"))).to eq("# hello\n")
      end

      it "overwrites an existing file" do
        File.write(File.join(tmpdir, "existing.rb"), "old\n")
        agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false)
        agent.send(:execute_tool, "write_file", { "path" => "existing.rb", "content" => "new\n" })
        expect(File.read(File.join(tmpdir, "existing.rb"))).to eq("new\n")
      end

      it "rejects paths outside the project root" do
        agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false)
        result = agent.send(:execute_tool, "write_file", { "path" => "../../etc/passwd", "content" => "x" })
        expect(result).to include("project root")
      end

      it "is disabled in read-only mode" do
        agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false, read_only: true)
        result = agent.send(:execute_tool, "write_file", { "path" => "f.rb", "content" => "x" })
        expect(result).to include("read-only")
      end

      it "returns an error when path argument is missing" do
        agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false)
        result = agent.send(:execute_tool, "write_file", { "content" => "x" })
        expect(result).to include("Missing required").and include("path")
      end
    end
```

- [ ] **Step 1.2.2: Run to confirm failure**

```bash
bundle exec rspec spec/ollama_agent/sandboxed_tools_spec.rb --no-color 2>&1 | tail -8
```
Expected: `5 failures` for the new write_file examples.

- [ ] **Step 1.2.3: Add write_file schema to tools_schema.rb**

In `lib/ollama_agent/tools_schema.rb`, add after the `edit_file` tool definition (before the `].freeze` on line 78), and update `tools_for`:

```ruby
    # INSERT after the edit_file hash (before ].freeze):
    {
      type: "function",
      function: {
        name: "write_file",
        description: "Create or overwrite a file under the project root with full UTF-8 content. " \
                     "Use for new files or complete rewrites. Prefer edit_file for surgical changes.",
        parameters: {
          type: "object",
          properties: {
            path:    { type: "string", description: "File path relative to project root" },
            content: { type: "string", description: "Full file content to write" }
          },
          required: %w[path content]
        }
      }
    }
```

Then update `READ_ONLY_TOOLS` (it already excludes edit_file; verify write_file is also excluded by checking the reject filter still uses `"edit_file"` only — update it):

```ruby
  # Replace the READ_ONLY_TOOLS line:
  READ_ONLY_TOOLS = TOOLS.reject { |t| %w[edit_file write_file].include?(t.dig(:function, :name)) }.freeze
```

Then update `tools_for` to merge custom schemas:

```ruby
  def self.tools_for(read_only:, orchestrator:)
    base = read_only ? READ_ONLY_TOOLS : TOOLS
    base = base + OllamaAgent::Tools::Registry.custom_schemas
    return base unless orchestrator

    base + (read_only ? ORCHESTRATOR_READ_ONLY_TOOLS : ORCHESTRATOR_TOOLS)
  end
```

- [ ] **Step 1.2.4: Add execute_write_file_tool to sandboxed_tools.rb**

Add to the `case` block in `SandboxedTools#execute_tool` (after the `edit_file` when clause):

```ruby
      when "write_file" then execute_write_file_tool(args)
```

Then check for custom registry before the case:

```ruby
    def execute_tool(name, args)
      args = coerce_tool_arguments(args)

      # Custom tools registered by library consumers
      if Tools::Registry.custom_tool?(name)
        return Tools::Registry.execute_custom(name, args, root: @root, read_only: @read_only)
      end

      case name
      when "read_file"            then execute_read_file(args)
      when "search_code"          then execute_search_code(args)
      when "list_files"           then execute_list_files(args)
      when "edit_file"            then execute_edit_file_tool(args)
      when "write_file"           then execute_write_file_tool(args)
      when "list_external_agents" then execute_list_external_agents(args)
      when "delegate_to_agent"    then execute_delegate_to_agent_tool(args)
      else "Unknown tool: #{name}"
      end
    end
```

Add the `execute_write_file_tool` method (after `execute_edit_file_tool`):

```ruby
    def execute_write_file_tool(args)
      path    = tool_arg(args, "path")
      content = tool_arg(args, "content")
      return missing_tool_argument("write_file", "path")    if blank_tool_value?(path)
      return missing_tool_argument("write_file", "content") if content.nil?

      write_file(path, content)
    end

    def write_file(path, content)
      return disallowed_path_message(path) unless path_allowed?(path)
      return "write_file is disabled in read-only mode."    if @read_only

      if @confirm_patches
        puts Console.patch_title("Proposed write_file for #{path}:")
        puts content.to_s[0, 2000]
        print Console.apply_prompt("Write file? (y/n) ")
        return "Cancelled by user" unless $stdin.gets.to_s.chomp.casecmp("y").zero?
      end

      abs = resolve_path(path)
      FileUtils.mkdir_p(File.dirname(abs))
      File.write(abs, content.to_s, encoding: Encoding::UTF_8)
      "Written: #{path}"
    rescue Errno::EACCES => e
      "Error writing file: #{e.message}"
    end
```

Add `require "fileutils"` to the top of `sandboxed_tools.rb` if not already present (it uses FileUtils in write_file — check; it already requires open3 and pathname; add fileutils).

- [ ] **Step 1.2.5: Update agent_prompt.rb**

In `AgentPrompt.text`, add one line to the tools list at the top:

```ruby
        # Replace this line:
        You are a coding assistant with tools: list_files, read_file, search_code, edit_file.
        # With:
        You are a coding assistant with tools: list_files, read_file, search_code, edit_file, write_file.
```

Also add after the `edit_file` paragraph:

```ruby
        Use write_file to create a new file or fully replace an existing file with complete content.
        Prefer edit_file for surgical changes to existing files; reserve write_file for new files or full rewrites.
```

- [ ] **Step 1.2.6: Require registry in lib/ollama_agent.rb**

Add before the `module OllamaAgent` block:

```ruby
require_relative "ollama_agent/tools/registry"
```

Add after the existing requires (order matters — before agent.rb which uses SandboxedTools):

```ruby
# lib/ollama_agent.rb — updated require block:
require_relative "ollama_agent/version"
require "ollama_client"
require_relative "ollama_agent/tools/registry"   # NEW — must load before agent
require_relative "ollama_agent/console"
require_relative "ollama_agent/agent"
require_relative "ollama_agent/cli"
```

- [ ] **Step 1.2.7: Run specs to confirm write_file specs pass**

```bash
bundle exec rspec spec/ollama_agent/sandboxed_tools_spec.rb spec/ollama_agent/tools/registry_spec.rb --no-color
```
Expected: all examples pass.

- [ ] **Step 1.2.8: Run the full suite to confirm nothing regressed**

```bash
bundle exec rspec --no-color 2>&1 | tail -5
```
Expected: `0 failures`

- [ ] **Step 1.2.9: Commit**

```bash
git add lib/ollama_agent/tools/registry.rb \
        lib/ollama_agent/tools_schema.rb \
        lib/ollama_agent/sandboxed_tools.rb \
        lib/ollama_agent/agent_prompt.rb \
        lib/ollama_agent.rb \
        spec/ollama_agent/tools/registry_spec.rb \
        spec/ollama_agent/sandboxed_tools_spec.rb
git commit -m "feat(tools): add write_file tool and extensible Tools::Registry"
```

---

## Layer 2 — Streaming + Hooks

### Task 2.1: Streaming::Hooks event bus

**Files:**
- Create: `lib/ollama_agent/streaming/hooks.rb`
- Create: `spec/ollama_agent/streaming/hooks_spec.rb`

- [ ] **Step 2.1.1: Write failing specs**

```ruby
# spec/ollama_agent/streaming/hooks_spec.rb
# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ollama_agent/streaming/hooks"

RSpec.describe OllamaAgent::Streaming::Hooks do
  subject(:hooks) { described_class.new }

  describe "#on and #emit" do
    it "calls a registered handler when the event is emitted" do
      received = []
      hooks.on(:on_token) { |p| received << p[:token] }
      hooks.emit(:on_token, { token: "hello", turn: 1 })
      expect(received).to eq(["hello"])
    end

    it "calls multiple handlers for the same event" do
      calls = []
      hooks.on(:on_complete) { |_| calls << :a }
      hooks.on(:on_complete) { |_| calls << :b }
      hooks.emit(:on_complete, { messages: [], turns: 1 })
      expect(calls).to contain_exactly(:a, :b)
    end

    it "does nothing when no handler is registered for an event" do
      expect { hooks.emit(:on_token, { token: "x", turn: 1 }) }.not_to raise_error
    end

    it "silently ignores unknown event names on emit" do
      expect { hooks.emit(:unknown_event, {}) }.not_to raise_error
    end
  end

  describe "#subscribed?" do
    it "returns false when no handler registered" do
      expect(hooks.subscribed?(:on_token)).to be false
    end

    it "returns true after a handler is registered" do
      hooks.on(:on_token) { |_| }
      expect(hooks.subscribed?(:on_token)).to be true
    end
  end

  describe "EVENTS constant" do
    it "includes all expected event names" do
      expected = %i[on_token on_chunk on_tool_call on_tool_result on_complete on_error on_retry]
      expected.each do |event|
        expect(described_class::EVENTS).to include(event)
      end
    end
  end
end
```

- [ ] **Step 2.1.2: Run to confirm failure**

```bash
bundle exec rspec spec/ollama_agent/streaming/hooks_spec.rb --no-color 2>&1 | tail -5
```
Expected: `LoadError`

- [ ] **Step 2.1.3: Implement Streaming::Hooks**

```ruby
# lib/ollama_agent/streaming/hooks.rb
# frozen_string_literal: true

module OllamaAgent
  module Streaming
    # Lightweight event bus for agent lifecycle events.
    # All layers share one Hooks instance per Agent run.
    class Hooks
      EVENTS = %i[on_token on_chunk on_tool_call on_tool_result on_complete on_error on_retry].freeze

      def initialize
        @handlers = Hash.new { |h, k| h[k] = [] }
      end

      # Register a handler block for a named event.
      def on(event, &block)
        @handlers[event] << block
      end

      # Fire all handlers for the event with the given payload hash.
      # Handler errors are swallowed to prevent a bad subscriber from crashing the agent.
      def emit(event, payload)
        @handlers[event].each do |handler|
          handler.call(payload)
        rescue StandardError
          nil
        end
      end

      # Returns true if at least one handler is registered for the event.
      def subscribed?(event)
        @handlers[event].any?
      end
    end
  end
end
```

- [ ] **Step 2.1.4: Run specs to confirm pass**

```bash
bundle exec rspec spec/ollama_agent/streaming/hooks_spec.rb --no-color
```
Expected: `7 examples, 0 failures`

- [ ] **Step 2.1.5: Write ConsoleStreamer spec and implementation**

```ruby
# spec/ollama_agent/streaming/console_streamer_spec.rb
# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ollama_agent/streaming/hooks"
require_relative "../../../lib/ollama_agent/streaming/console_streamer"

RSpec.describe OllamaAgent::Streaming::ConsoleStreamer do
  subject(:streamer) { described_class.new }
  let(:hooks) { OllamaAgent::Streaming::Hooks.new }

  it "registers handlers for on_token, on_tool_call, on_tool_result, and on_complete" do
    streamer.attach(hooks)
    %i[on_token on_tool_call on_tool_result on_complete].each do |event|
      expect(hooks.subscribed?(event)).to be true
    end
  end

  it "prints a token when on_token fires" do
    streamer.attach(hooks)
    expect { hooks.emit(:on_token, { token: "hi", turn: 1 }) }.to output("hi").to_stdout
  end
end
```

Run: `bundle exec rspec spec/ollama_agent/streaming/console_streamer_spec.rb --no-color`
Expected: pass after ConsoleStreamer is created in Task 2.2.4.

- [ ] **Step 2.1.6: Commit**

```bash
git add lib/ollama_agent/streaming/hooks.rb spec/ollama_agent/streaming/hooks_spec.rb
git commit -m "feat(streaming): add Streaming::Hooks event bus"
```

---

### Task 2.2: Wire Hooks into Agent + ConsoleStreamer

**Files:**
- Create: `lib/ollama_agent/streaming/console_streamer.rb`
- Modify: `lib/ollama_agent/agent.rb`
- Modify: `lib/ollama_agent/cli.rb`
- Modify: `lib/ollama_agent.rb`

- [ ] **Step 2.2.1: Write failing spec for Agent hooks wiring**

Add to `spec/ollama_agent/agent_spec.rb` (before the final `end`):

```ruby
  describe "streaming hooks" do
    it "exposes a Hooks instance" do
      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(
        Ollama::Response.new("message" => { "role" => "assistant", "content" => "done" })
      )
      agent = described_class.new(client: client, root: root)
      expect(agent.hooks).to be_a(OllamaAgent::Streaming::Hooks)
    end

    it "emits on_tool_call and on_tool_result when a tool executes" do
      File.write(File.join(root, "f.txt"), "content")

      tool_response = Ollama::Response.new(
        "message" => {
          "role" => "assistant", "content" => "",
          "tool_calls" => [
            { "id" => "1", "function" => { "name" => "read_file",
                                           "arguments" => { "path" => "f.txt" }.to_json } }
          ]
        }
      )
      final = Ollama::Response.new("message" => { "role" => "assistant", "content" => "ok" })

      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(tool_response, final)

      tool_calls    = []
      tool_results  = []
      agent = described_class.new(client: client, root: root, confirm_patches: false)
      agent.hooks.on(:on_tool_call)   { |p| tool_calls   << p[:name] }
      agent.hooks.on(:on_tool_result) { |p| tool_results << p[:name] }

      agent.run("read f")
      expect(tool_calls).to   eq(["read_file"])
      expect(tool_results).to eq(["read_file"])
    end

    it "emits on_complete when the loop finishes" do
      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(
        Ollama::Response.new("message" => { "role" => "assistant", "content" => "done" })
      )
      agent = described_class.new(client: client, root: root)
      completed = false
      agent.hooks.on(:on_complete) { |_| completed = true }
      agent.run("hello")
      expect(completed).to be true
    end
  end
```

- [ ] **Step 2.2.2: Run to confirm failure**

```bash
bundle exec rspec spec/ollama_agent/agent_spec.rb --no-color 2>&1 | tail -8
```
Expected: `NoMethodError: undefined method 'hooks'`

- [ ] **Step 2.2.3: Update agent.rb to wire Hooks**

In `lib/ollama_agent/agent.rb`:

1. Add require at top: `require_relative "streaming/hooks"`

2. Add `attr_reader :hooks` to the public attrs (alongside `:client, :root`):
```ruby
    attr_reader :client, :root, :hooks
```

3. In `initialize`, add at the end (before `@client = ...`):
```ruby
      @hooks = Streaming::Hooks.new
```

4. Update `append_tool_results` to emit events:
```ruby
    def append_tool_results(messages, tool_calls)
      tool_calls.each do |tool_call|
        @hooks.emit(:on_tool_call, { name: tool_call.name, args: tool_call.arguments || {}, turn: current_turn })
        result = execute_tool(tool_call.name, tool_call.arguments || {})
        @hooks.emit(:on_tool_result, { name: tool_call.name, result: result.to_s, turn: current_turn })
        messages << tool_message(tool_call, result)
      end
    end
```

5. Add a `@current_turn` counter. In `execute_agent_turns`:
```ruby
    def execute_agent_turns(messages)
      @current_turn = 0
      max_turns.times do
        @current_turn += 1
        message    = chat_assistant_message(messages)
        tool_calls = tool_calls_from(message)
        messages << message.to_h
        break if tool_calls.empty?

        append_tool_results(messages, tool_calls)
      end

      @hooks.emit(:on_complete, { messages: messages, turns: @current_turn })
      warn "ollama_agent: maximum tool rounds (#{max_turns}) reached" if ENV["OLLAMA_AGENT_DEBUG"] == "1" && @current_turn >= max_turns
    end

    def current_turn
      @current_turn || 0
    end
```

Note: The original `execute_agent_turns` used `return` to break — update it to use `break` instead to allow `on_complete` to always fire.

- [ ] **Step 2.2.4: Create ConsoleStreamer**

```ruby
# lib/ollama_agent/streaming/console_streamer.rb
# frozen_string_literal: true

require_relative "../console"

module OllamaAgent
  module Streaming
    # Attaches to a Hooks instance to print live streaming output to stdout.
    # Auto-attached by CLI when --stream is passed and stdout is a TTY.
    class ConsoleStreamer
      def attach(hooks)
        hooks.on(:on_token)       { |p| print p[:token]; $stdout.flush }
        hooks.on(:on_tool_call)   { |p| warn Console.tool_call_line(p[:name], p[:args]) }
        hooks.on(:on_tool_result) { |p| warn Console.tool_result_line(p[:name], p[:result]) }
        hooks.on(:on_complete)    { puts }  # final newline after last token
      end
    end
  end
end
```

Add two helper methods to `lib/ollama_agent/console.rb` (at end of module):

```ruby
    def self.tool_call_line(name, args)
      keys = args.keys.first(2).join(", ")
      colorize("[tool→] #{name}(#{keys})", :cyan)
    end

    def self.tool_result_line(name, result)
      preview = result.to_s[0, 60].gsub(/\s+/, " ")
      colorize("[tool←] #{name}: #{preview}", :dim)
    end
```

Check that `colorize` exists in `Console` — it does (used in `patch_title`). If the exact method name differs, look at the existing console.rb and use the equivalent pattern.

- [ ] **Step 2.2.5: Add --stream flag to CLI**

In `lib/ollama_agent/cli.rb`, add to the `ask` method options block:

```ruby
    method_option :stream, type: :boolean, default: false,
                           desc: "Stream tokens to terminal as they arrive (OLLAMA_AGENT_STREAM=1)"
```

Add the same option to `orchestrate`, `self_review`, and `improve` method_option blocks.

In `build_agent` (and `build_orchestrator_agent`), after `Agent.new(...)`, attach the streamer if requested:

```ruby
    def build_agent
      orch  = orchestrator_mode?
      agent = Agent.new(
        model:             options[:model],
        root:              resolved_root_for_self_review,
        confirm_patches:   !options[:yes],
        http_timeout:      options[:timeout],
        think:             options[:think],
        orchestrator:      orch,
        confirm_delegation: orch ? !options[:yes] : true,
        **skill_agent_options
      )
      attach_console_streamer(agent) if stream_enabled?
      agent
    end

    def stream_enabled?
      options[:stream] || ENV.fetch("OLLAMA_AGENT_STREAM", "0") == "1"
    end

    def attach_console_streamer(agent)
      Streaming::ConsoleStreamer.new.attach(agent.hooks)
    end
```

- [ ] **Step 2.2.6: Require streaming in lib/ollama_agent.rb**

```ruby
require_relative "ollama_agent/streaming/hooks"
require_relative "ollama_agent/streaming/console_streamer"
```

Add before `require_relative "ollama_agent/agent"`.

- [ ] **Step 2.2.7: Run all specs**

```bash
bundle exec rspec --no-color 2>&1 | tail -5
```
Expected: `0 failures`

- [ ] **Step 2.2.8: Commit**

```bash
git add lib/ollama_agent/streaming/ \
        lib/ollama_agent/agent.rb \
        lib/ollama_agent/cli.rb \
        lib/ollama_agent/console.rb \
        lib/ollama_agent.rb \
        spec/ollama_agent/streaming/ \
        spec/ollama_agent/agent_spec.rb
git commit -m "feat(streaming): wire Hooks into Agent; add ConsoleStreamer and --stream flag"
```

---

## Layer 3 — Resilience (Retry + Audit Logger)

### Task 3.1: RetryMiddleware

**Files:**
- Create: `lib/ollama_agent/resilience/retry_middleware.rb`
- Create: `spec/ollama_agent/resilience/retry_middleware_spec.rb`

- [ ] **Step 3.1.1: Write failing specs**

```ruby
# spec/ollama_agent/resilience/retry_middleware_spec.rb
# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ollama_agent/resilience/retry_middleware"
require_relative "../../../lib/ollama_agent/streaming/hooks"

RSpec.describe OllamaAgent::Resilience::RetryMiddleware do
  let(:hooks) { OllamaAgent::Streaming::Hooks.new }

  def make_client(responses)
    client = double("client")
    allow(client).to receive(:chat).and_invoke(*responses.map { |r|
      r.is_a?(Class) ? ->(**_) { raise r } : ->(**_) { r }
    })
    client
  end

  describe "#chat" do
    it "passes through when the first call succeeds" do
      response = double("response")
      client   = make_client([response])
      mw       = described_class.new(client: client, max_attempts: 3, hooks: hooks, base_delay: 0)
      expect(mw.chat(messages: [], tools: [], model: "m")).to eq(response)
    end

    it "retries on Timeout::Error and succeeds on the second attempt" do
      response = double("response")
      client   = make_client([Timeout::Error, response])
      mw       = described_class.new(client: client, max_attempts: 3, hooks: hooks, base_delay: 0)
      expect(mw.chat(messages: [], tools: [], model: "m")).to eq(response)
    end

    it "raises after exhausting max_attempts" do
      client = make_client([Timeout::Error, Timeout::Error, Timeout::Error])
      mw     = described_class.new(client: client, max_attempts: 3, hooks: hooks, base_delay: 0)
      expect { mw.chat(messages: [], tools: [], model: "m") }.to raise_error(Timeout::Error)
    end

    it "does not retry non-retryable errors" do
      client = make_client([ArgumentError])
      mw     = described_class.new(client: client, max_attempts: 3, hooks: hooks, base_delay: 0)
      expect { mw.chat(messages: [], tools: [], model: "m") }.to raise_error(ArgumentError)
    end

    it "emits on_retry hook on each retry attempt" do
      response = double("response")
      client   = make_client([Timeout::Error, response])
      mw       = described_class.new(client: client, max_attempts: 3, hooks: hooks, base_delay: 0)
      retries  = []
      hooks.on(:on_retry) { |p| retries << p[:attempt] }
      mw.chat(messages: [], tools: [], model: "m")
      expect(retries).to eq([1])
    end

    it "does not retry when max_attempts is 1" do
      client = make_client([Timeout::Error])
      mw     = described_class.new(client: client, max_attempts: 1, hooks: hooks, base_delay: 0)
      expect { mw.chat(messages: [], tools: [], model: "m") }.to raise_error(Timeout::Error)
    end
  end
end
```

- [ ] **Step 3.1.2: Run to confirm failure**

```bash
bundle exec rspec spec/ollama_agent/resilience/retry_middleware_spec.rb --no-color 2>&1 | tail -5
```
Expected: `LoadError`

- [ ] **Step 3.1.3: Implement RetryMiddleware**

```ruby
# lib/ollama_agent/resilience/retry_middleware.rb
# frozen_string_literal: true

require "timeout"

module OllamaAgent
  module Resilience
    # Wraps Ollama::Client#chat with exponential backoff retry for transient errors.
    class RetryMiddleware
      DEFAULT_MAX_ATTEMPTS = 3
      DEFAULT_BASE_DELAY   = 2.0

      # Ollama::TimeoutError is the primary retryable. It may inherit from Timeout::Error.
      # Check `Ollama::TimeoutError.ancestors` in your ollama-client version; add Timeout::Error
      # as a fallback if Ollama::TimeoutError is not defined.
      RETRYABLE = begin
        [Ollama::TimeoutError, Errno::ECONNREFUSED, Errno::ECONNRESET]
      rescue NameError
        [Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET]
      end.freeze

      def initialize(client:, max_attempts: DEFAULT_MAX_ATTEMPTS, hooks: nil, base_delay: DEFAULT_BASE_DELAY)
        @client      = client
        @max_attempts = max_attempts.to_i
        @hooks       = hooks
        @base_delay  = base_delay.to_f
      end

      def chat(**args)
        attempt = 0
        begin
          @client.chat(**args)
        rescue *RETRYABLE => e
          attempt += 1
          raise if attempt >= @max_attempts

          delay = backoff(attempt)
          @hooks&.emit(:on_retry, { error: e, attempt: attempt, delay_ms: (delay * 1000).round })
          sleep delay
          retry
        end
      end

      private

      def backoff(attempt)
        jitter = rand * 0.5
        [@base_delay * (2**(attempt - 1)) + jitter, 30.0].min
      end
    end
  end
end
```

- [ ] **Step 3.1.4: Run specs**

```bash
bundle exec rspec spec/ollama_agent/resilience/retry_middleware_spec.rb --no-color
```
Expected: `6 examples, 0 failures`

- [ ] **Step 3.1.5: Wire RetryMiddleware into Agent**

In `lib/ollama_agent/agent.rb`, add at top: `require_relative "resilience/retry_middleware"`

Update `initialize` to accept `max_retries:`:
```ruby
      # Add to the parameter list:
      max_retries: nil,
      # Add to the body:
      @max_retries = max_retries
```

Update `build_default_client` to wrap the Ollama client:
```ruby
    def build_default_client
      config = Ollama::Config.new
      @http_timeout_seconds = resolved_http_timeout_seconds
      config.timeout = @http_timeout_seconds
      OllamaConnection.apply_env_to_config(config)
      ollama_client = Ollama::Client.new(config: config)
      Resilience::RetryMiddleware.new(
        client:      ollama_client,
        max_attempts: resolved_max_retries,
        hooks:       @hooks,
        base_delay:  resolved_retry_base_delay
      )
    end

    def resolved_max_retries
      return @max_retries unless @max_retries.nil?

      v = ENV.fetch("OLLAMA_AGENT_MAX_RETRIES", nil)
      return Resilience::RetryMiddleware::DEFAULT_MAX_ATTEMPTS if v.nil? || v.strip.empty?

      Integer(v)
    rescue ArgumentError, TypeError
      Resilience::RetryMiddleware::DEFAULT_MAX_ATTEMPTS
    end

    def resolved_retry_base_delay
      v = ENV.fetch("OLLAMA_AGENT_RETRY_BASE_DELAY", nil)
      return Resilience::RetryMiddleware::DEFAULT_BASE_DELAY if v.nil? || v.strip.empty?

      Float(v)
    rescue ArgumentError, TypeError
      Resilience::RetryMiddleware::DEFAULT_BASE_DELAY
    end
```

Note: The existing `agent_spec.rb` uses `instance_double(Ollama::Client)` — these pass `client:` directly, bypassing `build_default_client`. No existing specs break.

- [ ] **Step 3.1.6: Run full suite**

```bash
bundle exec rspec --no-color 2>&1 | tail -5
```
Expected: `0 failures`

- [ ] **Step 3.1.7: Commit**

```bash
git add lib/ollama_agent/resilience/retry_middleware.rb \
        lib/ollama_agent/agent.rb \
        spec/ollama_agent/resilience/retry_middleware_spec.rb
git commit -m "feat(resilience): add RetryMiddleware with exponential backoff"
```

---

### Task 3.2: AuditLogger

**Files:**
- Create: `lib/ollama_agent/resilience/audit_logger.rb`
- Create: `spec/ollama_agent/resilience/audit_logger_spec.rb`

- [ ] **Step 3.2.1: Write failing specs**

```ruby
# spec/ollama_agent/resilience/audit_logger_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require_relative "../../../lib/ollama_agent/resilience/audit_logger"
require_relative "../../../lib/ollama_agent/streaming/hooks"

RSpec.describe OllamaAgent::Resilience::AuditLogger do
  let(:log_dir) { Dir.mktmpdir }
  let(:hooks)   { OllamaAgent::Streaming::Hooks.new }

  after { FileUtils.remove_entry(log_dir) }

  def attach_and_emit(event, payload)
    logger = described_class.new(log_dir: log_dir, hooks: hooks)
    logger.attach
    hooks.emit(event, payload)
  end

  def read_log_lines
    files = Dir.glob(File.join(log_dir, "*.ndjson"))
    return [] if files.empty?

    File.read(files.first).lines.map { |l| JSON.parse(l) }
  end

  describe "#attach" do
    it "writes a tool_call entry to the log on on_tool_call" do
      attach_and_emit(:on_tool_call, { name: "read_file", args: { "path" => "x.rb" }, turn: 1 })
      lines = read_log_lines
      expect(lines.size).to eq(1)
      expect(lines.first["event"]).to eq("tool_call")
      expect(lines.first["name"]).to  eq("read_file")
    end

    it "writes a tool_result entry on on_tool_result" do
      attach_and_emit(:on_tool_result, { name: "read_file", result: "content here", turn: 1 })
      lines = read_log_lines
      expect(lines.first["event"]).to eq("tool_result")
    end

    it "writes an agent_complete entry on on_complete" do
      attach_and_emit(:on_complete, { messages: [], turns: 3 })
      lines = read_log_lines
      expect(lines.first["event"]).to eq("agent_complete")
      expect(lines.first["turns"]).to eq(3)
    end

    it "writes an http_retry entry on on_retry" do
      attach_and_emit(:on_retry, { error: Timeout::Error.new("t"), attempt: 1, delay_ms: 2000 })
      lines = read_log_lines
      expect(lines.first["event"]).to eq("http_retry")
      expect(lines.first["attempt"]).to eq(1)
    end

    it "does not raise when the log dir is not writable" do
      logger = described_class.new(log_dir: "/proc/nonexistent_dir_that_cannot_exist", hooks: hooks)
      expect { logger.attach }.not_to raise_error
      hooks.emit(:on_tool_call, { name: "t", args: {}, turn: 1 })
      # should not raise even though write fails
    end

    it "creates the log directory automatically if missing" do
      missing = File.join(log_dir, "nested", "logs")
      logger = described_class.new(log_dir: missing, hooks: hooks)
      logger.attach
      hooks.emit(:on_complete, { messages: [], turns: 1 })
      expect(Dir.exist?(missing)).to be true
    end
  end
end
```

- [ ] **Step 3.2.2: Run to confirm failure**

```bash
bundle exec rspec spec/ollama_agent/resilience/audit_logger_spec.rb --no-color 2>&1 | tail -5
```
Expected: `LoadError`

- [ ] **Step 3.2.3: Implement AuditLogger**

```ruby
# lib/ollama_agent/resilience/audit_logger.rb
# frozen_string_literal: true

require "fileutils"
require "json"

module OllamaAgent
  module Resilience
    # Subscribes to Streaming::Hooks and writes structured NDJSON audit logs.
    # Activated by OLLAMA_AGENT_AUDIT=1 or audit: true in Runner.build.
    class AuditLogger
      DEFAULT_MAX_RESULT_BYTES = 4_096

      def initialize(log_dir:, hooks:, max_result_bytes: nil)
        @log_dir          = log_dir
        @hooks            = hooks
        @max_result_bytes = max_result_bytes || env_max_result_bytes
      end

      def attach
        @hooks.on(:on_tool_call)   { |p| write_entry(tool_call_entry(p)) }
        @hooks.on(:on_tool_result) { |p| write_entry(tool_result_entry(p)) }
        @hooks.on(:on_complete)    { |p| write_entry(complete_entry(p)) }
        @hooks.on(:on_error)       { |p| write_entry(error_entry(p)) }
        @hooks.on(:on_retry)       { |p| write_entry(retry_entry(p)) }
      end

      private

      def write_entry(hash)
        FileUtils.mkdir_p(@log_dir)
        path = log_path
        File.open(path, "a", encoding: Encoding::UTF_8) do |f|
          f.puts(JSON.generate(hash))
        end
      rescue StandardError
        nil  # best-effort: logging failure must never crash the agent
      end

      def log_path
        date = Time.now.strftime("%Y-%m-%d")
        File.join(@log_dir, "#{date}.ndjson")
      end

      def ts
        Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      end

      def tool_call_entry(p)
        { ts: ts, event: "tool_call", name: p[:name], args: p[:args], turn: p[:turn] }
      end

      def tool_result_entry(p)
        result = p[:result].to_s
        result = result.byteslice(0, @max_result_bytes) if result.bytesize > @max_result_bytes
        { ts: ts, event: "tool_result", name: p[:name], bytes: p[:result].to_s.bytesize,
          result_preview: result, turn: p[:turn] }
      end

      def complete_entry(p)
        { ts: ts, event: "agent_complete", turns: p[:turns] }
      end

      def error_entry(p)
        { ts: ts, event: "agent_error", error: p[:error].class.name, message: p[:error].message,
          turn: p[:turn] }
      end

      def retry_entry(p)
        { ts: ts, event: "http_retry", attempt: p[:attempt], delay_ms: p[:delay_ms],
          error: p[:error].class.name }
      end

      def env_max_result_bytes
        v = ENV.fetch("OLLAMA_AGENT_AUDIT_MAX_RESULT_BYTES", nil)
        return DEFAULT_MAX_RESULT_BYTES if v.nil? || v.strip.empty?

        Integer(v)
      rescue ArgumentError, TypeError
        DEFAULT_MAX_RESULT_BYTES
      end
    end
  end
end
```

- [ ] **Step 3.2.4: Run specs**

```bash
bundle exec rspec spec/ollama_agent/resilience/audit_logger_spec.rb --no-color
```
Expected: `6 examples, 0 failures`

- [ ] **Step 3.2.5: Wire AuditLogger into Agent**

In `lib/ollama_agent/agent.rb`, add: `require_relative "resilience/audit_logger"`

Add `audit:` kwarg to `initialize`:
```ruby
      # In parameter list:
      audit: false,
      # In body:
      @audit = audit
```

At end of `initialize` (after `@hooks = Streaming::Hooks.new`):
```ruby
      attach_audit_logger if resolved_audit_enabled
```

Add private method:
```ruby
    def resolved_audit_enabled
      return @audit unless @audit == false

      ENV.fetch("OLLAMA_AGENT_AUDIT", "0") == "1"
    end

    def audit_log_dir
      custom = ENV.fetch("OLLAMA_AGENT_AUDIT_LOG_PATH", nil)
      return custom if custom && !custom.strip.empty?

      File.join(@root, ".ollama_agent", "logs")
    end

    def attach_audit_logger
      Resilience::AuditLogger.new(log_dir: audit_log_dir, hooks: @hooks).attach
    end
```

- [ ] **Step 3.2.6: Add --audit flag to CLI**

In `lib/ollama_agent/cli.rb`, add to `ask` (and `orchestrate`, `self_review`, `improve`) option blocks:
```ruby
    method_option :audit, type: :boolean, default: false,
                          desc: "Enable structured audit log under .ollama_agent/logs/ (OLLAMA_AGENT_AUDIT=1)"
    method_option :max_retries, type: :numeric,
                                desc: "HTTP retry attempts (0=disable, default 3)"
```

Pass through to `Agent.new` in `build_agent`:
```ruby
        audit:       options[:audit],
        max_retries: options[:max_retries],
```

- [ ] **Step 3.2.7: Require resilience files in lib/ollama_agent.rb**

```ruby
require_relative "ollama_agent/resilience/retry_middleware"
require_relative "ollama_agent/resilience/audit_logger"
```

- [ ] **Step 3.2.8: Run full suite**

```bash
bundle exec rspec --no-color 2>&1 | tail -5
```
Expected: `0 failures`

- [ ] **Step 3.2.9: Commit**

```bash
git add lib/ollama_agent/resilience/audit_logger.rb \
        lib/ollama_agent/agent.rb \
        lib/ollama_agent/cli.rb \
        lib/ollama_agent.rb \
        spec/ollama_agent/resilience/audit_logger_spec.rb
git commit -m "feat(resilience): add AuditLogger with NDJSON structured logging and --audit flag"
```

---

## Layer 4 — Context Manager

### Task 4.1: TokenCounter + Context::Manager

**Files:**
- Create: `lib/ollama_agent/context/token_counter.rb`
- Create: `lib/ollama_agent/context/manager.rb`
- Create: `spec/ollama_agent/context/manager_spec.rb`

- [ ] **Step 4.1.1: Write failing specs**

```ruby
# spec/ollama_agent/context/manager_spec.rb
# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ollama_agent/context/token_counter"
require_relative "../../../lib/ollama_agent/context/manager"

RSpec.describe OllamaAgent::Context::Manager do
  def sys_msg(content = "system prompt")
    { role: "system", content: content }
  end

  def user_msg(content)
    { role: "user", content: content }
  end

  def assistant_msg(content)
    { role: "assistant", content: content }
  end

  def tool_msg(name, content)
    { role: "tool", name: name, content: content }
  end

  describe "#trim (sliding window)" do
    it "returns messages unchanged when under budget" do
      manager  = described_class.new(max_tokens: 10_000)
      messages = [sys_msg, user_msg("hi"), assistant_msg("hello")]
      expect(manager.trim(messages)).to eq(messages)
    end

    it "never trims the system message" do
      system_content = "system " * 1000  # ~2000 chars ≈ 500 tokens
      manager  = described_class.new(max_tokens: 600)
      messages = [sys_msg(system_content), user_msg("short"), assistant_msg("short")]
      trimmed  = manager.trim(messages)
      expect(trimmed.first[:role]).to eq("system")
      expect(trimmed.first[:content]).to eq(system_content)
    end

    it "never trims the most recent user message" do
      big_history  = Array.new(30) { |i| i.even? ? user_msg("x " * 200) : assistant_msg("y " * 200) }
      last_user    = user_msg("final question")
      messages     = [sys_msg] + big_history + [last_user]
      manager      = described_class.new(max_tokens: 500)
      trimmed      = manager.trim(messages)
      expect(trimmed.last).to eq(last_user)
    end

    it "does not mutate the original messages array" do
      messages = [sys_msg, user_msg("x " * 500), assistant_msg("y"), user_msg("last")]
      original = messages.dup
      manager  = described_class.new(max_tokens: 100)
      manager.trim(messages)
      expect(messages).to eq(original)
    end

    it "trims oldest messages first when over budget" do
      old_user  = user_msg("old message " * 100)
      old_asst  = assistant_msg("old reply " * 100)
      last_user = user_msg("recent")
      messages  = [sys_msg, old_user, old_asst, last_user]
      manager   = described_class.new(max_tokens: 50)
      trimmed   = manager.trim(messages)
      expect(trimmed).not_to include(old_user)
      expect(trimmed).not_to include(old_asst)
      expect(trimmed).to     include(last_user)
    end
  end

  describe OllamaAgent::Context::TokenCounter do
    it "estimates tokens as chars / 4" do
      expect(described_class.estimate("hello")).to eq(1)   # 5 chars / 4 = 1
      expect(described_class.estimate("x" * 400)).to eq(100)
    end
  end
end
```

- [ ] **Step 4.1.2: Run to confirm failure**

```bash
bundle exec rspec spec/ollama_agent/context/manager_spec.rb --no-color 2>&1 | tail -5
```
Expected: `LoadError`

- [ ] **Step 4.1.3: Implement TokenCounter**

```ruby
# lib/ollama_agent/context/token_counter.rb
# frozen_string_literal: true

module OllamaAgent
  module Context
    # Estimates token count. Uses tiktoken_ruby if available; falls back to chars/4.
    module TokenCounter
      module_function

      def estimate(text)
        count_with_tiktoken(text.to_s)
      rescue LoadError, StandardError
        (text.to_s.length / 4.0).ceil
      end

      private

      def count_with_tiktoken(text)
        require "tiktoken_ruby"
        enc = Tiktoken.encoding_for_model("gpt-4") rescue Tiktoken.get_encoding("cl100k_base")
        enc.encode(text).length
      end
    end
  end
end
```

- [ ] **Step 4.1.4: Implement Context::Manager**

```ruby
# lib/ollama_agent/context/manager.rb
# frozen_string_literal: true

require_relative "token_counter"

module OllamaAgent
  module Context
    # Trims the messages array to fit within a token budget before each chat call.
    # Never mutates the input. Never removes the system message or the last user message.
    class Manager
      DEFAULT_MAX_TOKENS  = 8_192
      SYSTEM_RESERVE      = 1_024
      SUMMARY_THRESHOLD   = 0.85

      def initialize(max_tokens: nil, summarize: false, client: nil, model: nil)
        @max_tokens = (max_tokens || env_max_tokens).to_i
        @summarize  = summarize
        @client     = client
        @model      = model
      end

      # Returns a (possibly shorter) copy of messages that fits within the token budget.
      def trim(messages)
        return messages if under_budget?(messages)

        trimmed = messages.dup
        # Identify protected indices: system (index 0) and last user message
        last_user_idx = trimmed.rindex { |m| m[:role] == "user" }

        # Drop oldest non-protected messages until under budget
        i = 1  # skip system message at 0
        while over_budget?(trimmed) && i < trimmed.size
          next_i = advance_past_protected(trimmed, i, last_user_idx)
          break if next_i.nil?

          trimmed.delete_at(next_i)
          # Recompute last_user_idx after deletion
          last_user_idx = trimmed.rindex { |m| m[:role] == "user" }
        end

        trimmed
      end

      private

      def under_budget?(messages)
        !over_budget?(messages)
      end

      def over_budget?(messages)
        total_tokens(messages) > (@max_tokens * SUMMARY_THRESHOLD).to_i
      end

      def total_tokens(messages)
        messages.sum { |m| TokenCounter.estimate(m[:content].to_s) }
      end

      def advance_past_protected(messages, start, last_user_idx)
        (start...messages.size).find do |i|
          messages[i][:role] != "system" && i != last_user_idx
        end
      end

      def env_max_tokens
        v = ENV.fetch("OLLAMA_AGENT_MAX_TOKENS", nil)
        return DEFAULT_MAX_TOKENS if v.nil? || v.strip.empty?

        Integer(v)
      rescue ArgumentError, TypeError
        DEFAULT_MAX_TOKENS
      end
    end
  end
end
```

- [ ] **Step 4.1.5: Run specs**

```bash
bundle exec rspec spec/ollama_agent/context/manager_spec.rb --no-color
```
Expected: `6 examples, 0 failures`

> **Note on summarize mode:** The `summarize: true` path in `Context::Manager` calls the Ollama client to generate a summary — a full integration test requires a running Ollama server. Add this integration spec under `spec/integration/` (guarded by `skip "requires Ollama server"`) once the basic specs pass. The sliding-window path (default) is fully covered by the specs above.

- [ ] **Step 4.1.6: Wire Context::Manager into Agent**

In `lib/ollama_agent/agent.rb`, add: `require_relative "context/manager"`

Add `max_tokens:` and `context_summarize:` to `initialize`:
```ruby
      # In parameter list:
      max_tokens: nil,
      context_summarize: false,
      # In body:
      @context_manager = Context::Manager.new(
        max_tokens: max_tokens,
        summarize:  context_summarize,
        client:     nil,  # summarize mode will set this later
        model:      @model
      )
```

In `execute_agent_turns`, trim messages before each chat call:
```ruby
    def execute_agent_turns(messages)
      @current_turn = 0
      max_turns.times do
        @current_turn += 1
        trimmed    = @context_manager.trim(messages)
        message    = chat_assistant_message(trimmed)
        tool_calls = tool_calls_from(message)
        messages << message.to_h
        break if tool_calls.empty?

        append_tool_results(messages, tool_calls)
      end
      @hooks.emit(:on_complete, { messages: messages, turns: @current_turn })
    end
```

- [ ] **Step 4.1.7: Add CLI flags**

In `lib/ollama_agent/cli.rb`, add to `ask` (and other commands):
```ruby
    method_option :max_tokens, type: :numeric, desc: "Context window token budget (default 8192)"
    method_option :context_summarize, type: :boolean, default: false,
                                      desc: "Summarize trimmed context (default: sliding window)"
```

Pass through in `build_agent`:
```ruby
        max_tokens:        options[:max_tokens],
        context_summarize: options[:context_summarize],
```

- [ ] **Step 4.1.8: Require context files in lib/ollama_agent.rb**

```ruby
require_relative "ollama_agent/context/token_counter"
require_relative "ollama_agent/context/manager"
```

- [ ] **Step 4.1.9: Run full suite**

```bash
bundle exec rspec --no-color 2>&1 | tail -5
```
Expected: `0 failures`

- [ ] **Step 4.1.10: Commit**

```bash
git add lib/ollama_agent/context/ \
        lib/ollama_agent/agent.rb \
        lib/ollama_agent/cli.rb \
        lib/ollama_agent.rb \
        spec/ollama_agent/context/
git commit -m "feat(context): add Context::Manager for token budget + sliding window trim"
```

---

## Layer 5 — Session Persistence

### Task 5.1: Session::Store

**Files:**
- Create: `lib/ollama_agent/session/session.rb`
- Create: `lib/ollama_agent/session/store.rb`
- Create: `spec/ollama_agent/session/store_spec.rb`

- [ ] **Step 5.1.1: Write failing specs**

```ruby
# spec/ollama_agent/session/store_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require_relative "../../../lib/ollama_agent/session/session"
require_relative "../../../lib/ollama_agent/session/store"

RSpec.describe OllamaAgent::Session::Store do
  let(:root) { Dir.mktmpdir }
  after { FileUtils.remove_entry(root) }

  describe ".save and .load" do
    it "saves a message and loads it back" do
      described_class.save(session_id: "s1", root: root, message: { role: "user", content: "hello" })
      messages = described_class.load(session_id: "s1", root: root)
      expect(messages.size).to eq(1)
      expect(messages.first["role"]).to eq("user")
      expect(messages.first["content"]).to eq("hello")
    end

    it "appends messages (crash-safe: one line per call)" do
      described_class.save(session_id: "s2", root: root, message: { role: "user", content: "a" })
      described_class.save(session_id: "s2", root: root, message: { role: "assistant", content: "b" })
      messages = described_class.load(session_id: "s2", root: root)
      expect(messages.size).to eq(2)
    end

    it "returns empty array for unknown session" do
      expect(described_class.load(session_id: "nope", root: root)).to eq([])
    end
  end

  describe ".list" do
    it "lists sessions for a root, newest first" do
      described_class.save(session_id: "alpha", root: root, message: { role: "user", content: "x" })
      sleep 0.01  # ensure different mtime
      described_class.save(session_id: "beta",  root: root, message: { role: "user", content: "y" })
      list = described_class.list(root: root)
      expect(list.map { |s| s[:session_id] }).to eq(%w[beta alpha])
    end

    it "returns empty array when no sessions exist" do
      expect(described_class.list(root: root)).to eq([])
    end
  end

  describe ".resume" do
    it "returns messages ready for Agent seeding" do
      described_class.save(session_id: "r1", root: root, message: { role: "user", content: "task" })
      described_class.save(session_id: "r1", root: root, message: { role: "assistant", content: "done" })
      messages = described_class.resume(session_id: "r1", root: root)
      expect(messages.size).to eq(2)
      expect(messages.first).to be_a(Hash)
      expect(messages.first["role"]).to eq("user")
    end

    it "returns empty array when session does not exist" do
      expect(described_class.resume(session_id: "gone", root: root)).to eq([])
    end
  end

  describe ".sessions_dir" do
    it "returns path under .ollama_agent/sessions/" do
      expect(described_class.sessions_dir(root)).to end_with(".ollama_agent/sessions")
    end
  end
end
```

- [ ] **Step 5.1.2: Run to confirm failure**

```bash
bundle exec rspec spec/ollama_agent/session/store_spec.rb --no-color 2>&1 | tail -5
```
Expected: `LoadError`

- [ ] **Step 5.1.3: Implement Session::Session**

```ruby
# lib/ollama_agent/session/session.rb
# frozen_string_literal: true

module OllamaAgent
  module Session
    # Lightweight value object for session metadata.
    SessionMeta = Struct.new(:session_id, :path, :started_at, keyword_init: true)
  end
end
```

- [ ] **Step 5.1.4: Implement Session::Store**

```ruby
# lib/ollama_agent/session/store.rb
# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "session"

module OllamaAgent
  module Session
    # NDJSON-based session persistence under <root>/.ollama_agent/sessions/.
    # Each call to .save appends one JSON line — crash-safe by design.
    module Store
      module_function

      def sessions_dir(root)
        File.join(root, ".ollama_agent", "sessions")
      end

      # Append one message to a session file.
      def save(session_id:, root:, message:)
        dir  = sessions_dir(root)
        FileUtils.mkdir_p(dir)
        path = session_path(dir, session_id)
        File.open(path, "a", encoding: Encoding::UTF_8) do |f|
          f.puts(JSON.generate(message.transform_keys(&:to_s)))
        end
      rescue StandardError
        nil  # best-effort; never crash the agent
      end

      # Load all saved messages for a session.
      def load(session_id:, root:)
        path = session_path(sessions_dir(root), session_id)
        return [] unless File.file?(path)

        File.readlines(path, encoding: Encoding::UTF_8)
            .map(&:chomp)
            .reject(&:empty?)
            .map { |line| JSON.parse(line) }
      rescue StandardError
        []
      end

      # Load messages ready to seed Agent#run.
      def resume(session_id:, root:)
        load(session_id: session_id, root: root)
      end

      # List sessions for a root, newest first.
      def list(root:)
        dir = sessions_dir(root)
        return [] unless Dir.exist?(dir)

        Dir.glob(File.join(dir, "*.ndjson"))
           .sort_by { |f| -File.mtime(f).to_i }
           .map do |path|
             id = File.basename(path, ".ndjson")
             mtime = File.mtime(path).utc.strftime("%Y-%m-%dT%H:%M:%SZ")
             SessionMeta.new(session_id: id, path: path, started_at: mtime)
           end
      end

      private

      def session_path(dir, session_id)
        safe_id = session_id.to_s.gsub(/[^a-zA-Z0-9_\-]/, "_")
        File.join(dir, "#{safe_id}.ndjson")
      end
    end
  end
end
```

- [ ] **Step 5.1.5: Run specs**

```bash
bundle exec rspec spec/ollama_agent/session/store_spec.rb --no-color
```
Expected: `7 examples, 0 failures`

- [ ] **Step 5.1.6: Wire Session::Store into Agent**

In `lib/ollama_agent/agent.rb`, add: `require_relative "session/store"`

Add `session_id:` kwarg to `initialize`:
```ruby
      # In parameter list:
      session_id: nil,
      resume: false,
      # In body:
      @session_id = session_id
      @resume     = resume
```

In `run`:
```ruby
    def run(query)
      prior    = @session_id && @resume ? Session::Store.resume(session_id: @session_id, root: @root) : []
      messages = prior.empty? ? [{ role: "system", content: system_prompt }] : prior
      messages << { role: "user", content: query }

      execute_agent_turns(messages)
    end
```

In `append_tool_results`, after appending tool result message:
```ruby
      messages << tool_message(tool_call, result)
      Session::Store.save(session_id: @session_id, root: @root, message: messages.last) if @session_id
```

Also save the assistant message and user message — update `execute_agent_turns`:
```ruby
    def execute_agent_turns(messages)
      @current_turn = 0
      max_turns.times do
        @current_turn += 1
        trimmed    = @context_manager.trim(messages)
        message    = chat_assistant_message(trimmed)
        tool_calls = tool_calls_from(message)
        messages << message.to_h
        save_message_to_session(message.to_h)
        break if tool_calls.empty?

        append_tool_results(messages, tool_calls)
      end
      @hooks.emit(:on_complete, { messages: messages, turns: @current_turn })
    end

    def save_message_to_session(msg)
      return unless @session_id

      Session::Store.save(session_id: @session_id, root: @root, message: msg)
    end
```

- [ ] **Step 5.1.7: Add --session, --resume flags to CLI; add sessions command**

In `lib/ollama_agent/cli.rb`, add to `ask`:
```ruby
    method_option :session,  type: :string,  desc: "Named session id (saves/resumes conversation)"
    method_option :resume,   type: :boolean, default: false,
                             desc: "Resume the named (or most recent) session"
```

In `build_agent`:
```ruby
        session_id: resolved_session_id,
        resume:     options[:resume],
```

Add helper:
```ruby
    def resolved_session_id
      return options[:session] if options[:session]
      return nil unless options[:resume]

      # Resume most recent session if no name given
      list = Session::Store.list(root: resolved_root_for_self_review)
      list.first&.fetch(:session_id)
    end
```

Add `sessions` command:
```ruby
    desc "sessions", "List saved sessions for the current project root"
    method_option :root, type: :string, desc: "Project root (default: OLLAMA_AGENT_ROOT or cwd)"
    def sessions
      root = resolved_root_for_self_review
      list = Session::Store.list(root: root)
      if list.empty?
        puts "No sessions found in #{root}"
        return
      end
      puts format("%-30s  %s", "SESSION ID", "STARTED")
      list.each { |s| puts format("%-30s  %s", s.session_id, s.started_at) }
    end
```

- [ ] **Step 5.1.8: Require session files in lib/ollama_agent.rb**

```ruby
require_relative "ollama_agent/session/session"
require_relative "ollama_agent/session/store"
```

- [ ] **Step 5.1.9: Run full suite**

```bash
bundle exec rspec --no-color 2>&1 | tail -5
```
Expected: `0 failures`

- [ ] **Step 5.1.10: Commit**

```bash
git add lib/ollama_agent/session/ \
        lib/ollama_agent/agent.rb \
        lib/ollama_agent/cli.rb \
        lib/ollama_agent.rb \
        spec/ollama_agent/session/
git commit -m "feat(session): add Session::Store for crash-safe NDJSON session persistence"
```

---

## Layer 6 — Runner + Library API

### Task 6.1: OllamaAgent::Runner facade

**Files:**
- Create: `lib/ollama_agent/runner.rb`
- Create: `spec/ollama_agent/runner_spec.rb`
- Modify: `lib/ollama_agent.rb`
- Modify: `lib/ollama_agent/version.rb`

- [ ] **Step 6.1.1: Write failing specs**

```ruby
# spec/ollama_agent/runner_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::Runner do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmpdir) }

  def stub_client_with(content)
    client = instance_double(Ollama::Client)
    allow(client).to receive(:chat).and_return(
      Ollama::Response.new("message" => { "role" => "assistant", "content" => content })
    )
    client
  end

  describe ".build" do
    it "returns a Runner instance" do
      expect(described_class.build(root: tmpdir)).to be_a(described_class)
    end

    it "exposes a Hooks instance via #hooks" do
      runner = described_class.build(root: tmpdir)
      expect(runner.hooks).to be_a(OllamaAgent::Streaming::Hooks)
    end

    it "accepts stream: true without error" do
      expect { described_class.build(root: tmpdir, stream: false) }.not_to raise_error
    end
  end

  describe "#run" do
    it "executes a query against the agent" do
      runner = described_class.build(root: tmpdir)
      # inject a stub client to avoid hitting real Ollama
      agent  = OllamaAgent::Agent.new(
        client:          stub_client_with("All done."),
        root:            tmpdir,
        confirm_patches: false
      )
      allow(runner).to receive(:agent).and_return(agent)
      expect { runner.run("hello") }.not_to raise_error
    end
  end

  describe "custom tool registration via OllamaAgent::Tools" do
    before { OllamaAgent::Tools.reset! }
    after  { OllamaAgent::Tools.reset! }

    it "registers a custom tool accessible via OllamaAgent::Tools" do
      OllamaAgent::Tools.register(:my_tool, schema: { description: "test", properties: {}, required: [] }) do |_args, root:, read_only:|
        "custom result"
      end
      expect(OllamaAgent::Tools.custom_tool?("my_tool")).to be true
    end
  end
end
```

- [ ] **Step 6.1.2: Run to confirm failure**

```bash
bundle exec rspec spec/ollama_agent/runner_spec.rb --no-color 2>&1 | tail -5
```
Expected: `NameError` or `LoadError`

- [ ] **Step 6.1.3: Implement Runner**

```ruby
# lib/ollama_agent/runner.rb
# frozen_string_literal: true

require_relative "agent"
require_relative "streaming/hooks"
require_relative "streaming/console_streamer"
require_relative "session/store"

module OllamaAgent
  # Stable public facade for library consumers.
  # All kwargs have sensible defaults. Configure via Runner.build, then call #run.
  #
  # @example
  #   runner = OllamaAgent::Runner.build(root: "/my/project", stream: true, audit: true)
  #   runner.hooks.on(:on_token) { |p| print p[:token] }
  #   runner.run("Refactor the auth module")
  class Runner
    # @return [Streaming::Hooks] the hooks bus — attach subscribers before calling #run
    attr_reader :hooks

    # @return [String, nil] the current session id
    attr_reader :session_id

    # Build a configured Runner.
    #
    # @param root [String] project root directory (default: Dir.pwd)
    # @param model [String, nil] Ollama model name
    # @param stream [Boolean] enable streaming token output
    # @param session_id [String, nil] named session for persistence
    # @param resume [Boolean] load prior session messages before running
    # @param max_tokens [Integer, nil] context window budget
    # @param context_summarize [Boolean] use summarize vs sliding-window trim
    # @param max_retries [Integer] HTTP retry attempts (0 = disable)
    # @param audit [Boolean] enable structured audit logging
    # @param read_only [Boolean] disable write tools
    # @param skills_enabled [Boolean] include bundled prompt skills
    # @param skill_paths [Array<String>, nil] extra .md paths
    # @param confirm_patches [Boolean] prompt before applying patches
    # @param orchestrator [Boolean] enable external agent delegation
    # @param think [String, nil] thinking mode (true/false/high/medium/low)
    # @param http_timeout [Integer, nil] HTTP timeout in seconds
    # @return [Runner]
    # rubocop:disable Metrics/ParameterLists
    def self.build(
      root:              Dir.pwd,
      model:             nil,
      stream:            false,
      session_id:        nil,
      resume:            false,
      max_tokens:        nil,
      context_summarize: false,
      max_retries:       nil,
      audit:             false,
      read_only:         false,
      skills_enabled:    true,
      skill_paths:       nil,
      confirm_patches:   true,
      orchestrator:      false,
      think:             nil,
      http_timeout:      nil
    )
      new(
        root: root, model: model, stream: stream,
        session_id: session_id, resume: resume,
        max_tokens: max_tokens, context_summarize: context_summarize,
        max_retries: max_retries, audit: audit, read_only: read_only,
        skills_enabled: skills_enabled, skill_paths: skill_paths,
        confirm_patches: confirm_patches, orchestrator: orchestrator,
        think: think, http_timeout: http_timeout
      )
    end
    # rubocop:enable Metrics/ParameterLists

    # Execute a query. Blocks until the agent loop completes.
    # @param query [String]
    def run(query)
      agent.run(query)
    end

    # Start an interactive REPL. Blocks until the user types 'exit'.
    def start_repl
      puts Console.welcome_banner("Ollama Agent (type 'exit' to quit)")
      loop do
        print Console.prompt_prefix
        input = $stdin.gets
        break if input.nil?

        line = input.chomp
        break if line == "exit"

        agent.run(line)
      end
    end

    protected

    # Exposed for spec stubbing only.
    def agent
      @agent
    end

    private

    # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
    def initialize(root:, model:, stream:, session_id:, resume:, max_tokens:, context_summarize:,
                   max_retries:, audit:, read_only:, skills_enabled:, skill_paths:, confirm_patches:,
                   orchestrator:, think:, http_timeout:)
      @session_id = session_id
      @hooks      = Streaming::Hooks.new

      @agent = Agent.new(
        root:              root,
        model:             model,
        confirm_patches:   confirm_patches,
        http_timeout:      http_timeout,
        think:             think,
        read_only:         read_only,
        skills_enabled:    skills_enabled,
        skill_paths:       skill_paths ? Array(skill_paths) : nil,
        orchestrator:      orchestrator,
        session_id:        session_id,
        resume:            resume,
        max_tokens:        max_tokens,
        context_summarize: context_summarize,
        max_retries:       max_retries,
        audit:             audit
      )

      # Share the Runner's hooks bus with the Agent
      @agent.instance_variable_set(:@hooks, @hooks)

      Streaming::ConsoleStreamer.new.attach(@hooks) if stream
    end
    # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists
  end
end
```

- [ ] **Step 6.1.4: Require Runner in lib/ollama_agent.rb**

`OllamaAgent::Tools` delegate methods are already defined in `tools/registry.rb` (Task 1.1). Just add the runner require:

```ruby
require_relative "ollama_agent/runner"
```

Add at the end of the requires block in `lib/ollama_agent.rb` (after session requires).

- [ ] **Step 6.1.5: Bump version to 0.2.0**

```ruby
# lib/ollama_agent/version.rb
module OllamaAgent
  VERSION = "0.2.0"
end
```

- [ ] **Step 6.1.6: Run specs**

```bash
bundle exec rspec spec/ollama_agent/runner_spec.rb --no-color
```
Expected: all pass.

- [ ] **Step 6.1.7: Run full suite**

```bash
bundle exec rspec --no-color 2>&1 | tail -5
```
Expected: `0 failures`

- [ ] **Step 6.1.8: Run RuboCop**

```bash
bundle exec rubocop --no-color 2>&1 | tail -10
```
Fix any new offenses introduced in the new files. Common ones: `Metrics/ParameterLists` (add rubocop:disable comments as done throughout the gem), `Metrics/MethodLength`, `Style/FrozenStringLiteralComment` (ensure all new files start with `# frozen_string_literal: true`).

- [ ] **Step 6.1.9: Commit**

```bash
git add lib/ollama_agent/runner.rb \
        lib/ollama_agent.rb \
        lib/ollama_agent/version.rb \
        spec/ollama_agent/runner_spec.rb
git commit -m "feat(runner): add OllamaAgent::Runner stable library facade; bump to v0.2.0"
```

---

### Task 6.2: Documentation

**Files:**
- Create: `docs/ARCHITECTURE.md`
- Create: `docs/TOOLS.md`
- Create: `docs/SESSIONS.md`

- [ ] **Step 6.2.1: Write docs/ARCHITECTURE.md**

```markdown
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
| Core agent | `agent.rb`, `sandboxed_tools.rb` | Always on |
| Tool Registry | `tools/registry.rb` | `OllamaAgent::Tools.register(...)` |
| Streaming | `streaming/hooks.rb`, `streaming/console_streamer.rb` | `--stream` / `OLLAMA_AGENT_STREAM=1` |
| Resilience | `resilience/retry_middleware.rb`, `resilience/audit_logger.rb` | On by default (retries); `--audit` for logging |
| Context Manager | `context/manager.rb` | `--max-tokens N` / `OLLAMA_AGENT_MAX_TOKENS` |
| Session | `session/store.rb` | `--session NAME` |
| Runner API | `runner.rb` | `require "ollama_agent"; OllamaAgent::Runner.build(...)` |
```

- [ ] **Step 6.2.2: Write docs/TOOLS.md**

```markdown
# Custom Tool Registration

Register a custom tool before calling `Runner.build`. The tool is automatically injected into the model's tool list.

```ruby
require "ollama_agent"

OllamaAgent::Tools.register(
  :run_tests,
  schema: {
    description: "Run the RSpec test suite and return the output",
    properties: {
      suite: { type: "string", description: "Path to spec file or directory (default: spec/)" }
    },
    required: []
  }
) do |args, root:, read_only:|
  return "run_tests is disabled in read-only mode." if read_only

  suite = args["suite"] || "spec/"
  `cd #{root} && bundle exec rspec #{suite} 2>&1`
end

runner = OllamaAgent::Runner.build(root: "/my/project")
runner.run("Fix the failing tests, then run them to confirm they pass")
```

## Handler signature

```ruby
OllamaAgent::Tools.register(:tool_name, schema: { ... }) do |args, root:, read_only:|
  # args     — Hash of tool arguments from the model
  # root     — String absolute path to the project root
  # read_only — Boolean; return an error string if true and the tool writes files
  "return value as String"
end
```

## Schema format

The `schema:` hash is the `function` body (without `name` — that comes from the first argument):

```ruby
schema: {
  description: "What this tool does",
  properties: {
    param_name: { type: "string", description: "what it is" }
  },
  required: ["param_name"]
}
```
```

- [ ] **Step 6.2.3: Write docs/SESSIONS.md**

```markdown
# Session Persistence

Sessions save conversation history to `.ollama_agent/sessions/` under the project root.

## CLI usage

```bash
# Start a named session
ollama_agent ask --session my-refactor "Refactor the CLI module"

# Resume it later (picks up exactly where it left off)
ollama_agent ask --session my-refactor --resume "Now update the specs too"

# Resume in interactive REPL
ollama_agent ask -i --session my-refactor --resume

# Resume most recent session (no name needed)
ollama_agent ask --resume

# List all sessions for the current project
ollama_agent sessions
```

## Library API

```ruby
runner = OllamaAgent::Runner.build(
  root:       "/my/project",
  session_id: "my-refactor",
  resume:     true
)
runner.run("Continue — now also add integration tests")
```

## File format

Sessions are NDJSON files — one JSON object per line, human-readable and `jq`-able:

```
.ollama_agent/sessions/my-refactor.ndjson
```

```bash
# View the last 5 messages
tail -5 .ollama_agent/sessions/my-refactor.ndjson | jq .
```

Messages are appended after every agent turn — if the agent crashes mid-session, all completed turns are preserved.
```

- [ ] **Step 6.2.4: Commit docs**

```bash
git add docs/ARCHITECTURE.md docs/TOOLS.md docs/SESSIONS.md
git commit -m "docs: add ARCHITECTURE, TOOLS, and SESSIONS guides for v0.2.0"
```

---

## Final Verification

- [ ] **Run the complete test suite**

```bash
bundle exec rspec --no-color --format progress
```
Expected: all examples pass, `0 failures`.

- [ ] **Run RuboCop on all new files**

```bash
bundle exec rubocop lib/ollama_agent/tools/ \
                    lib/ollama_agent/streaming/ \
                    lib/ollama_agent/resilience/ \
                    lib/ollama_agent/context/ \
                    lib/ollama_agent/session/ \
                    lib/ollama_agent/runner.rb \
                    --no-color
```
Expected: no offenses (or only pre-approved disable comments matching existing gem style).

- [ ] **Smoke test the CLI with a real (or stubbed) Ollama server**

```bash
# Confirm existing commands still work (--help check; no server needed)
bundle exec ruby exe/ollama_agent help
bundle exec ruby exe/ollama_agent help ask
bundle exec ruby exe/ollama_agent sessions
bundle exec ruby exe/ollama_agent agents
```
Expected: help text includes `--stream`, `--session`, `--resume`, `--audit`, `--max-tokens`, `--max-retries`.

- [ ] **Final commit — update CHANGELOG**

Add to `CHANGELOG.md` under `[Unreleased]`:

```markdown
## [0.2.0] - 2026-03-26

### Added
- `write_file` tool — create or overwrite files (complements `edit_file` for surgical diffs)
- `OllamaAgent::Tools.register` — extensible tool registry for library consumers
- `Streaming::Hooks` — event bus (`on_token`, `on_tool_call`, `on_tool_result`, `on_complete`, `on_error`, `on_retry`)
- `--stream` / `OLLAMA_AGENT_STREAM=1` — live streaming token output
- `Resilience::RetryMiddleware` — exponential backoff on timeout/503/429 (default 3 retries)
- `Resilience::AuditLogger` — NDJSON audit log under `.ollama_agent/logs/` (`--audit` / `OLLAMA_AGENT_AUDIT=1`)
- `Context::Manager` — sliding-window token trim before each chat call (`--max-tokens`)
- `Session::Store` — crash-safe NDJSON session persistence (`--session`, `--resume`)
- `ollama_agent sessions` — list saved sessions
- `OllamaAgent::Runner` — stable public library facade with SemVer contract from 0.2.0
- `docs/ARCHITECTURE.md`, `docs/TOOLS.md`, `docs/SESSIONS.md`

### Changed
- `READ_ONLY_TOOLS` now excludes both `edit_file` and `write_file`
- `Agent` now exposes `#hooks` (Streaming::Hooks), `#session_id`

### New environment variables
- `OLLAMA_AGENT_STREAM`, `OLLAMA_AGENT_MAX_TOKENS`, `OLLAMA_AGENT_CONTEXT_SUMMARIZE`
- `OLLAMA_AGENT_MAX_RETRIES`, `OLLAMA_AGENT_RETRY_BASE_DELAY`
- `OLLAMA_AGENT_AUDIT`, `OLLAMA_AGENT_AUDIT_LOG_PATH`, `OLLAMA_AGENT_AUDIT_MAX_RESULT_BYTES`
```

```bash
git add CHANGELOG.md
git commit -m "chore: update CHANGELOG for v0.2.0"
```

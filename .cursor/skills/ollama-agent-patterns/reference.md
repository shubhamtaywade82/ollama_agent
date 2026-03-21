# Reference: patterns & Ruby snippets

Concise examples for `ollama_agent`-style gems. Adapt names to the real `ollama-client` API.

## Factory Method + registry (`inherited`)

```ruby
# lib/ollama_agent/tools/base.rb
module OllamaAgent
  module Tools
    class Base
      def initialize(args)
        @args = args
      end

      def call
        raise NotImplementedError
      end

      def self.inherited(subclass)
        return if subclass.name.nil?

        name = subclass.name.split("::").last.underscore
        ToolRegistry.register(name, subclass)
      end
    end
  end
end

# lib/ollama_agent/tools/registry.rb — or tool_registry.rb at module root
module OllamaAgent
  module Tools
    class ToolRegistry
      @tools = {}
      class << self
        def register(name, klass)
          @tools[name.to_s] = klass
        end

        def get(name)
          @tools[name.to_s]
        end
      end
    end
  end
end
```

## Builder (`PromptBuilder`)

```ruby
class PromptBuilder
  attr_reader :messages, :tools, :options

  def initialize
    @messages = []
    @tools = []
    @options = {}
  end

  def system(content)
    @messages << { role: "system", content: content }
    self
  end

  def user(content)
    @messages << { role: "user", content: content }
    self
  end

  def add_tool(tool_def)
    @tools << tool_def
    self
  end

  def temperature(value)
    @options[:temperature] = value
    self
  end

  def build
    { messages: @messages, tools: @tools, options: @options }
  end
end
```

## Singleton (optional client holder)

```ruby
require "singleton"

class OllamaClientWrapper
  include Singleton

  attr_reader :client

  def initialize
    @client = Ollama::Client.new(model: ENV.fetch("OLLAMA_MODEL"))
  end
end
```

Prefer **dependency injection** of a client/adapter in tests instead of `Singleton` when practical.

## Adapter + Proxy

```ruby
# lib/ollama_agent/llm/base_adapter.rb
module OllamaAgent
  module LLM
    class BaseAdapter
      def chat(messages:, tools:, **options)
        raise NotImplementedError
      end
    end
  end
end

# lib/ollama_agent/llm/ollama_adapter.rb
module OllamaAgent
  module LLM
    class OllamaAdapter < BaseAdapter
      def initialize(client = Ollama::Client.new)
        @client = client
      end

      def chat(messages:, tools:, **options)
        @client.chat(messages: messages, tools: tools, **options)
      end
    end
  end
end

# lib/ollama_agent/llm/logging_proxy.rb
module OllamaAgent
  module LLM
    class LoggingProxy
      def initialize(adapter, logger: $stderr)
        @adapter = adapter
        @logger = logger
      end

      def chat(...)
        @logger.puts "LLM chat request"
        @adapter.chat(...)
      end
    end
  end
end
```

## Command (tool execution)

```ruby
class ToolCommand
  attr_reader :name, :args, :result

  def initialize(name, args)
    @name = name
    @args = args
  end

  def execute
    klass = Tools::ToolRegistry.get(@name)
    raise KeyError, "Unknown tool: #{@name}" unless klass

    @result = klass.new(@args).call
  end

  def undo
    # Optional: revert file edits, etc.
  end
end
```

## Observer (streaming)

```ruby
class Agent
  def initialize(adapter:)
    @adapter = adapter
    @observers = []
  end

  def add_observer(observer)
    @observers << observer
  end

  def notify_observers(token, logprobs)
    @observers.each { |obs| obs.update(token, logprobs) }
  end
end
```

Wire `on_token` (or equivalent) from `ollama-client` to `notify_observers`.

## Strategy (patch application)

```ruby
class PatchStrategy
  def apply(path, diff)
    raise NotImplementedError
  end
end

class SystemPatchStrategy < PatchStrategy
  def apply(path, diff)
    IO.popen(["patch", "-p1", "-f", path.to_s], "w") { |stdin| stdin.write(diff) }
  end
end
```

## State (conversation phases)

```ruby
class AgentState
  def handle(agent, response)
    raise NotImplementedError
  end
end

class IdleState < AgentState
  def handle(agent, response)
    # transition when tool calls appear
  end
end

class ToolExecutionState < AgentState
  def handle(agent, response)
    # run tools, append results, return to idle
  end
end
```

## Template Method (agent loop)

```ruby
class BaseAgent
  def run(query)
    messages = build_initial_messages(query)
    loop do
      response = send_to_llm(messages)
      if tool_calls?(response)
        messages << assistant_message(response)
        process_tool_calls(tool_calls(response), messages)
      else
        handle_final_response(response, messages)
        break
      end
    end
  end

  def build_initial_messages(query)
    raise NotImplementedError
  end

  def send_to_llm(messages)
    raise NotImplementedError
  end

  def process_tool_calls(_tool_calls, _messages)
    raise NotImplementedError
  end

  def handle_final_response(_response, _messages)
    raise NotImplementedError
  end
end
```

## Metaprogramming: tool DSL (optional)

```ruby
class BaseTool
  def self.tool(name, description, &block)
    define_method(:call, &block)
    Tools::ToolRegistry.register(name.to_s, self)
  end
end
```

Prefer explicit subclasses + `inherited` registration if the DSL obscures tests.

## Dynamic hooks

```ruby
def trigger_hook(event)
  m = :"on_#{event}"
  send(m) if respond_to?(m, true)
end
```

## Putting it together (illustrative)

```ruby
module OllamaAgent
  class Agent
    def initialize(adapter:, tool_registry: Tools::ToolRegistry)
      @adapter = adapter
      @tool_registry = tool_registry
      @state = IdleState.new
      @observers = []
    end

    def run(query)
      built = PromptBuilder.new
        .system(SYSTEM_PROMPT)
        .user(query)
        .temperature(0.2)
        .build

      messages = built[:messages]
      # Loop: @adapter.chat with messages/tools/options; @state.handle; execute tools via ToolCommand
    end

    def add_observer(observer)
      @observers << observer
    end

    def execute_tool(tool_call)
      klass = @tool_registry.get(tool_call.name)
      raise KeyError, "Unknown tool: #{tool_call.name}" unless klass

      command = ToolCommand.new(tool_call.name, tool_call.arguments)
      command.execute
      command.result
    end
  end
end
```

## Main entry `require` pattern

```ruby
# lib/ollama_agent.rb
require_relative "ollama_agent/version"
require_relative "ollama_agent/tool_registry"
require_relative "ollama_agent/tools/base"
Dir[File.join(__dir__, "ollama_agent", "tools", "*.rb")].sort.each { |f| require f }
# require LLM, commands, agent, cli
```

Skip globs if load order matters; require explicit files instead.

# ToolRuntime guide

`OllamaAgent::ToolRuntime` is a small **Ruby-first** agent loop for apps that define their **own** tools (outside the coding sandbox). Each step, a **planner** (usually an LLM) proposes a single JSON object `{"tool":"name","args":{...}}`; the runtime resolves the name, runs your tool, records the outcome, and repeats until a tool signals **done** or a safety limit trips.

It does **not** replace the CLI or `OllamaAgent::Agent` / `Runner` (those use Ollama **native** `/api/chat` tool calling for `read_file`, `edit_file`, etc.). Use ToolRuntime when you want **JSON-shaped plans** and **plain Ruby tool classes** in another domain (e.g. a separate gem that talks to your own APIs).

See also: [ARCHITECTURE.md](ARCHITECTURE.md) (coding-agent stack), [TOOLS.md](TOOLS.md) (custom tools **on** the coding agent).

---

## When to use it

| Use ToolRuntime | Use `Runner` / `Agent` instead |
|-----------------|-------------------------------|
| You implement `ToolRuntime::Tool` subclasses and a per-run `Registry` | You want file/search/patch tools under a project root |
| You want a **swappable** planner (`next_step(context:, memory:, registry:)`) | You want the stock Ollama tool-calling chat loop |
| You are OK prompting the model to emit **one JSON object per step** | You rely on Ollama’s structured `tool_calls` |

---

## Pieces you wire together

1. **`Tool`** — Subclass, implement `name`, `description`, `schema`, `call(args)`. `args` uses string keys (JSON-style).
2. **`Registry.new([tool, ...])`** — Looks up the planner’s `"tool"` string; duplicate names are rejected.
3. **`Memory`** — Short transcript; optional `memory.tool_descriptions = "..."` is prepended to the planner prompt (extra hints).
4. **`Executor`** — Optional `validator: object` with `validate(tool_name, args)` → args (or raise). Tool exceptions become `{ "status" => "error", "error" => "..." }`.
5. **`OllamaJsonPlanner`** — Calls `client.chat` with a user prompt listing tools + context + prior steps; parses **one** JSON object from the reply (see `JsonExtractor`).
6. **`Loop`** — `run(context:)` runs until a tool returns a Hash with `"status" => "done"` or `max_steps` is exceeded (`MaxStepsExceeded`).

**Return value:** `Loop#run` returns the **last tool result** (the Hash/object from the final `call` that ended the loop).

---

## Client and model (same rules as the CLI)

The planner uses your `Ollama::Client`. If you use **Ollama Cloud** env vars, build the config like the coding agent:

```ruby
require "ollama_agent"
require "ollama_client"

config = Ollama::Config.new
OllamaAgent::OllamaConnection.apply_env_to_config(config)
client = Ollama::Client.new(config: config)
```

`OllamaJsonPlanner` resolves the model like `Agent`: explicit `model:` keyword, else `ENV["OLLAMA_AGENT_MODEL"]`, else `Ollama::Config.new.model`.

**Common mistake:** `Ollama::Client.new(config: Ollama::Config.new)` without `apply_env_to_config` talks to **localhost** only. If `OLLAMA_AGENT_MODEL` is still a **cloud-only** tag, you get **404 model not found**. Either apply `apply_env_to_config`, or unset the env var, or pass `model: "your-local-tag"`.

The model should follow instructions to output **only** one JSON object per step (no markdown fences). If it drifts, you’ll see `JsonParseError`.

---

## Minimal runnable example

```ruby
require "ollama_agent"
require "ollama_client"

class EchoTool < OllamaAgent::ToolRuntime::Tool
  def name = "echo"
  def description = "Echo a message string"
  def schema = { "type" => "object", "properties" => { "msg" => { "type" => "string" } } }

  def call(args)
    return { "status" => "done", "echo" => args["msg"] } if args["msg"] == "bye"

    { "status" => "ok", "echo" => args["msg"] }
  end
end

registry = OllamaAgent::ToolRuntime::Registry.new([EchoTool.new])
memory = OllamaAgent::ToolRuntime::Memory.new

config = Ollama::Config.new
OllamaAgent::OllamaConnection.apply_env_to_config(config)
client = Ollama::Client.new(config: config)

planner = OllamaAgent::ToolRuntime::OllamaJsonPlanner.new(client: client)

last = OllamaAgent::ToolRuntime::Loop.new(
  planner: planner,
  registry: registry,
  executor: OllamaAgent::ToolRuntime::Executor.new,
  memory: memory,
  max_steps: 10
).run(context: "Use echo until you can call echo with msg bye to finish.")

puts last.inspect
puts memory.recent.inspect
```

---

## Inspecting what happened

- **`memory.recent`** — Array of `{ thought:, action:, result: }` (symbols). `thought` is the parsed plan Hash; `action` is `{ tool: <Tool instance>, args: Hash }`; `result` is what `Executor` returned.
- **`last` from `run`** — Final tool return value only (convenient for “answer” extraction).

---

## Custom planner

Anything that responds to:

```ruby
def next_step(context:, memory:, registry:)
  # return a Hash like { "tool" => "echo", "args" => { "msg" => "hi" } }
end
```

can be passed as `planner:` to `Loop`. That lets you swap in scripted tests, another LLM, or a hybrid without changing `Loop`.

---

## Validator example

```ruby
validator = Class.new do
  def validate(tool_name, args)
    raise ArgumentError, "missing msg" if tool_name == "echo" && args["msg"].to_s.empty?

    args
  end
end.new

executor = OllamaAgent::ToolRuntime::Executor.new(validator: validator)
```

---

## Errors you may see

| Error | Typical cause |
|-------|----------------|
| `Ollama::NotFoundError` (404 model) | Wrong host/model pair; see **Client and model** above |
| `OllamaAgent::ToolRuntime::JsonParseError` | Model did not return parseable JSON for one object |
| `InvalidPlanError` | Planner returned an unknown `"tool"` name |
| `MaxStepsExceeded` | No tool returned `"status" => "done"` before `max_steps` planner calls |

---

## Tests as examples

Executable examples live under:

`spec/ollama_agent/tool_runtime/`

Run:

```bash
bundle exec rspec spec/ollama_agent/tool_runtime
```

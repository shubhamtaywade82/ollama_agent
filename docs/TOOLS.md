# Tools

## Built-in agentic tools

These two tools ship with the gem and are available in all permission profiles.

### `list_directory_contents` — sandboxed filesystem inspection

Lists files and subdirectories at a path relative to the project root. All paths
are resolved with `File.expand_path` and rejected before the filesystem is touched
if they escape the workspace boundary (`OLLAMA_AGENT_ROOT` / `context[:root]`).

**Schema parameters**

| Parameter | Type   | Required | Description |
|-----------|--------|----------|-------------|
| `path`    | string | no       | Relative path inside the workspace (default: `.`) |

**Tool class:** `OllamaAgent::Tools::FilesystemExplorer`

**Example — use from the agent (CLI)**

```bash
bundle exec ruby exe/ollama_agent ask \
  "List the files in lib/ollama_agent/tools/ and describe each one."
```

**Example — call directly from Ruby**

```ruby
require "ollama_agent"

tool = OllamaAgent::Tools::FilesystemExplorer.new
puts tool.call({ "path" => "lib/ollama_agent/tools" }, context: { root: Dir.pwd })
# Contents of "lib/ollama_agent/tools" (8 item(s)):
#   [FILE] base.rb (2847 bytes)
#   [FILE] built_in_schemas.rb (5120 bytes)
#   …
```

**Security notes**

- `../../etc` → `Error: Access denied`
- `/etc/passwd` → `Error: Access denied`
- Path that does not exist → `Error: Path "x" does not exist`
- Path that is a file, not a directory → `Error: Path "x" is not a directory`

---

### `calculate` — safe arithmetic evaluator

Evaluates an arithmetic expression using a hand-written **Shunting-yard** tokenizer
and RPN stack evaluator. **`eval` is never called.** Only numeric literals and the
operators listed below are accepted; any other character is an error returned as a
string.

**Supported operators**

| Operator | Meaning          | Associativity |
|----------|------------------|---------------|
| `+`      | addition         | left          |
| `-`      | subtraction      | left          |
| `*`      | multiplication   | left          |
| `/`      | division         | left          |
| `**`     | exponentiation   | **right**     |
| unary `+`/`-` | sign     | right (prefix) |

Parentheses are supported. `2 ** 3 ** 2` evaluates to `512` (right-associative),
not `64`. Division by zero returns the string `"Error: result is non-finite
(division by zero?)"`.

**Schema parameters**

| Parameter    | Type   | Required | Description |
|--------------|--------|----------|-------------|
| `expression` | string | yes      | Arithmetic expression |

**Tool class:** `OllamaAgent::Tools::SafeCalculator`

**Example — use from the agent (CLI)**

```bash
bundle exec ruby exe/ollama_agent ask \
  "What is (412 + 1834 + 10786 + 88 + 2210) / 1024, rounded to two decimal places?"
```

**Example — call directly from Ruby**

```ruby
require "ollama_agent"

calc = OllamaAgent::Tools::SafeCalculator.new

puts calc.call({ "expression" => "(2 + 3) * 4" })          # "20.0"
puts calc.call({ "expression" => "2 ** 10" })               # "1024.0"
puts calc.call({ "expression" => "2 ** 3 ** 2" })           # "512.0"
puts calc.call({ "expression" => "(412 + 1834) / 1024" })   # "2.1933594…"
puts calc.call({ "expression" => "1 / 0" })                 # "Error: result is non-finite …"
puts calc.call({ "expression" => "2 + x" })                 # "Error: invalid character "x" …"
```

---

## Custom Tool Registration

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
  require "open3"
  output, = Open3.capture2("bundle", "exec", "rspec", suite, chdir: root)
  output
end

runner = OllamaAgent::Runner.build(root: "/my/project")
runner.run("Fix the failing tests, then run them to confirm they pass")
```

## Handler signature

```ruby
OllamaAgent::Tools.register(:tool_name, schema: { ... }) do |args, root:, read_only:|
  # args      — Hash of tool arguments from the model
  # root      — String absolute path to the project root
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

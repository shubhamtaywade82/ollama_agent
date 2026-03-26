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

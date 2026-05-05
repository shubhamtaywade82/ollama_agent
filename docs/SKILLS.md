# Skills

Skills are **single-purpose generators** that bypass the tool-calling agent
loop and return **strict JSON** validated against a schema. Use them when you
want predictable, parseable output — code review, refactoring suggestions,
performance audits, debugging triage, feature scaffolds — without the
unpredictability of free-form LLM prose.

The agent loop is the right tool when the model needs to *act* on the
filesystem. The skill system is the right tool when you want the model to
*report* something a downstream pipeline can consume.

## How a skill runs

```
prompt(input) → llm.generate → JsonExtractor.parse → SchemaValidator.validate! → Hash
```

1. `#prompt(input)` — your subclass renders a deterministic prompt.
2. `LlmClient#generate` — single-shot call against the configured provider
   (default: local Ollama, `temperature: 0`).
3. `JsonExtractor.parse` — extracts the first balanced JSON object from the
   response. Tolerates leading prose, trailing commentary, ```` ```json ````
   fences, and brackets nested inside JSON string literals.
4. `SchemaValidator.validate!` — checks the parsed payload against the
   subclass's `SCHEMA` constant. On mismatch, `Skills::Base::ContractError`.

## Built-in skills

| Skill id                | Purpose                                              |
| ----------------------- | ---------------------------------------------------- |
| `architecture_refactor` | Restructure code without changing behavior           |
| `performance_optimizer` | Identify bottlenecks and emit optimized code         |
| `debug_engineer`        | Root-cause a bug and propose a fix                   |
| `feature_builder`       | Design and implement a production-ready feature      |

Each lives in `lib/ollama_agent/skills/<name>.rb` and self-registers via
`register_as`.

## CLI

```bash
# list registered skills
ollama_agent skill list

# run a single skill, get pretty JSON on stdout
ollama_agent skill run architecture_refactor --code-file lib/orders/manager.rb

# debug from a stack trace
ollama_agent skill run debug_engineer \
  --code-file lib/positions/exit.rb \
  --error "NoMethodError: undefined method `ltp` for nil"

# scaffold a feature
ollama_agent skill run feature_builder \
  --requirements "Bracket-order watchdog with SL/TP drift detection"

# compose a pipeline; later skills receive earlier outputs merged in
ollama_agent skill pipeline architecture_refactor performance_optimizer \
  --code-file lib/exit_management.rb
```

Model resolution: `--model` → `OLLAMA_AGENT_SKILL_MODEL` →
`OLLAMA_AGENT_MODEL` → `llama3.2`.

## Ruby

```ruby
result = OllamaAgent::Skills::ArchitectureRefactorer.new.call(
  code: File.read("lib/orders/manager.rb")
)
# => { folder_structure: [...], architecture_notes: "...", refactored_code: "..." }

OllamaAgent::Skills::Runner.new(
  [:architecture_refactor, :performance_optimizer]
).call(code: File.read("lib/exit_management.rb"))
```

The `Runner` merges each skill's output into the accumulator so downstream
skills see both the original input and every prior result.

## Writing a custom skill

Three things make a skill: a `SCHEMA`, a `#prompt`, and a `register_as` call.

```ruby
# lib/my_app/skills/risk_engine_validator.rb
require "ollama_agent"

module MyApp
  module Skills
    class RiskEngineValidator < OllamaAgent::Skills::Base
      register_as :risk_engine_validator

      SCHEMA = {
        type: "object",
        required: %w[invariants violations remediation],
        properties: {
          invariants:  { type: "array" },
          violations:  { type: "array" },
          remediation: { type: "string", minLength: 1 }
        }
      }.freeze

      protected

      def validated_input!(input)
        super
        raise ArgumentError, "missing :code" if input[:code].to_s.strip.empty?
      end

      def prompt(input)
        <<~PROMPT
          You are a senior risk engineer.

          List the invariants the code must hold, find any violations, and
          propose remediation.

          Respond with ONLY a JSON object matching this contract:
          {
            "invariants": ["..."],
            "violations": ["..."],
            "remediation": "string"
          }

          CODE:
          #{input[:code]}
        PROMPT
      end
    end
  end
end
```

Once required, it's accessible everywhere skills are:

```bash
ollama_agent skill run risk_engine_validator --code-file lib/risk/engine.rb
```

```ruby
MyApp::Skills::RiskEngineValidator.new.call(code: File.read("lib/risk/engine.rb"))
```

### Schema vocabulary

`Core::SchemaValidator` is intentionally minimal — no JSON-schema gem needed.
Supported keywords:

- `type` — `object | array | string | integer | number | boolean | null`
- `required` — array of property names that must be present
- `properties` — per-key sub-schemas, recursively validated
- `enum` — allowed scalar values
- `minLength` / `maxLength` — string length bounds
- `minimum` / `maximum` — numeric bounds

If your contract needs something richer (`oneOf`, regex `pattern`, conditional
schemas), do the extra check inside an override of `#validate_contract!`:

```ruby
def validate_contract!(parsed)
  super
  raise ContractError, "remediation must mention SL/TP" unless parsed[:remediation].match?(/SL|TP/)
end
```

### Input validation

Override `#validated_input!` to fail fast on missing fields. The base class
already rejects non-Hash input.

```ruby
def validated_input!(input)
  super
  %i[code language].each do |key|
    raise ArgumentError, "missing :#{key}" if input[key].to_s.strip.empty?
  end
end
```

## Swapping the LLM client

Anything that responds to `#generate(prompt) → String` works:

```ruby
class FakeLlm
  def generate(_prompt)
    '{"invariants": [], "violations": [], "remediation": "n/a"}'
  end
end

MyApp::Skills::RiskEngineValidator.new(llm: FakeLlm.new).call(code: "...")
```

Use this in tests, or to plug in a non-default provider (`OpenAI`, `Anthropic`,
or a custom one registered via `Providers::Registry.register`).

```ruby
provider = OllamaAgent::Providers::Registry.resolve("anthropic")
llm      = OllamaAgent::Skills::LlmClient.new(provider: provider, model: "claude-3-5-sonnet-20241022")

OllamaAgent::Skills::ArchitectureRefactorer.new(llm: llm).call(code: "...")
```

## Packaging a skill in a plugin

Skills register themselves at file load time, so the only thing a plugin
needs to do is *load* the file. Drop your skill under one of the locations
`Plugins::Loader` searches and require it from the plugin entrypoint:

```
.ollama_agent/plugins/my_app/
  ├── plugin.rb               # entrypoint, auto-loaded
  └── skills/
      └── risk_engine_validator.rb
```

```ruby
# .ollama_agent/plugins/my_app/plugin.rb
require_relative "skills/risk_engine_validator"

OllamaAgent::Plugins::Registry.register(:my_app) do |r|
  # optional: also expose as a tool, prompt, or policy
end
```

Once loaded, `ollama_agent skill list` includes `risk_engine_validator` and
`ollama_agent skill run risk_engine_validator …` works end-to-end.

## Testing skills

Skills are pure functions of `(input, llm)`. Stub the LLM and assert on the
parsed payload:

```ruby
RSpec.describe MyApp::Skills::RiskEngineValidator do
  let(:fake_llm_class) { Class.new { def generate(_prompt); end } }
  let(:llm) { instance_double(fake_llm_class, generate: response) }

  context "with a well-formed contract response" do
    let(:response) { '{"invariants": [], "violations": [], "remediation": "ok"}' }

    it "returns the parsed payload" do
      result = described_class.new(llm: llm).call(code: "class Foo; end")
      expect(result).to include(:invariants, :violations, :remediation)
    end
  end

  context "with response missing required keys" do
    let(:response) { '{"remediation": "x"}' }

    it "raises ContractError" do
      expect { described_class.new(llm: llm).call(code: "class Foo; end") }
        .to raise_error(OllamaAgent::Skills::Base::ContractError)
    end
  end
end
```

See `spec/ollama_agent/skills/` in this repo for the patterns used by the
built-in skills.

## When to use a skill vs. the agent loop

| Want                                                       | Use                                                                |
| ---------------------------------------------------------- | ------------------------------------------------------------------ |
| The model to *modify* files                                | `Agent` / `Runner` / `ollama_agent ask`                            |
| Predictable JSON for a downstream pipeline                 | `Skills::Base` subclass                                            |
| Multi-step reasoning across many files                     | `Agent` (the tool loop), optionally with a session                 |
| One-shot analysis of a single file or brief                | A skill                                                            |
| Compose several deterministic stages (refactor → optimize) | `Skills::Runner`                                                   |
| Conversational back-and-forth                              | `Agent` in interactive / TUI mode                                  |

A common pattern is **skill first, agent second**: run a skill to plan, feed
the JSON into a templated user prompt, then hand it to the agent loop to
execute the changes.

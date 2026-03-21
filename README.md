# ollama_agent

Ruby gem that runs a **CLI coding agent** against a local [Ollama](https://ollama.com) model. It exposes tools to **list files**, **read files**, **search the tree** (ripgrep or grep), and **apply unified diffs** so the model can make small, reviewable edits.

## Requirements

- Ruby ≥ 3.2
- Ollama running and a capable tool-calling model (e.g. a coder variant)

## Installation

From RubyGems (when published) or from this repository:

```bash
bundle install
```

## Usage

From the project you want the agent to modify (set the working directory accordingly):

```bash
bundle exec ruby exe/ollama_agent ask "Update the README.md with current codebase"
```

Apply proposed patches without interactive confirmation:

```bash
bundle exec ruby exe/ollama_agent ask -y "Your task"
```

Interactive REPL:

```bash
bundle exec ruby exe/ollama_agent ask --interactive
```

### Environment

| Variable | Purpose |
|----------|---------|
| `OLLAMA_AGENT_MODEL` | Model name (overrides default from ollama-client) |
| `OLLAMA_AGENT_ROOT` | Project root (defaults to current working directory) |
| `OLLAMA_AGENT_DEBUG` | Set to `1` to print validation diagnostics on stderr |
| `OLLAMA_AGENT_MAX_TURNS` | Max chat rounds with tool calls (default: 64) |

## How it works

1. The CLI starts `OllamaAgent::Agent`, which loops on `Ollama::Client#chat` with tool definitions.
2. Tools are executed in-process under a **path sandbox** (`OLLAMA_AGENT_ROOT`).
3. Patches are validated and checked with **`patch --dry-run`** before you confirm (unless `-y`).

## Development

```bash
bundle exec rspec
bundle exec rubocop
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).

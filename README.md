# ollama_agent

Version: 0.1.0

Ruby gem that runs a **CLI coding agent** against a local [Ollama](https://ollama.com) model. It exposes tools to **list files**, **read files**, **search the tree** (ripgrep or grep), and **apply unified diffs** so the model can make small, reviewable edits.

## Features

- Tool `list_files` – list project files.
- Tool `read_file` – read file contents.
- Tool `search_code` – search code with ripgrep or grep.
- Tool `edit_file` – apply unified diffs safely.
- CLI built with Thor, entry point `exe/ollama_agent`.

## Requirements

- Ruby ≥ 3.2
- **Local:** Ollama running and a capable tool-calling model, **or**
- **Ollama Cloud:** API key and a cloud-capable model name (see below)

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

Long-running models (slow local inference):

```bash
bundle exec ruby exe/ollama_agent ask --timeout 300 "Your task"
```

Interactive REPL:

```bash
bundle exec ruby exe/ollama_agent ask --interactive
```

The CLI uses **ANSI colors** on a TTY (banner, prompt, patch prompts). **Assistant replies** are rendered as **Markdown** (headings, lists, bold, code fences) via `tty-markdown` when stdout is a TTY and **`NO_COLOR`** is unset. Disable Markdown rendering with **`OLLAMA_AGENT_MARKDOWN=0`**. Disable all colors with **`NO_COLOR`** or **`OLLAMA_AGENT_COLOR=0`**.

### Ollama Cloud

[Ollama Cloud](https://docs.ollama.com/cloud) uses the same HTTP API as the local server, with HTTPS and a Bearer API key. The **ollama-client** gem sends `Authorization: Bearer <api_key>` when `Ollama::Config#api_key` is set (HTTPS is used when the URL scheme is `https`).

1. Create a key at [ollama.com/settings/keys](https://ollama.com/settings/keys).
2. Point the agent at the cloud host and pass the key (same env names as ollama-client’s docs):

```bash
export OLLAMA_BASE_URL="https://ollama.com"
export OLLAMA_API_KEY="your_key"
export OLLAMA_AGENT_MODEL="gpt-oss:120b-cloud"   # example; pick a cloud model from `ollama list` / the catalog
bundle exec ruby exe/ollama_agent ask "Your task"
```

### Environment

| Variable | Purpose |
|----------|---------|
| `OLLAMA_BASE_URL` | Ollama API base URL (default from ollama-client: `http://localhost:11434`; use `https://ollama.com` for cloud) |
| `OLLAMA_API_KEY` | API key for Ollama Cloud (`https://ollama.com`); optional for local HTTP |
| `OLLAMA_AGENT_MODEL` | Model name (overrides default from ollama-client) |
| `OLLAMA_AGENT_ROOT` | Project root (defaults to current working directory) |
| `OLLAMA_AGENT_DEBUG` | Set to `1` to print validation diagnostics on stderr |
| `OLLAMA_AGENT_MAX_TURNS` | Max chat rounds with tool calls (default: 64) |
| `OLLAMA_AGENT_TIMEOUT` | HTTP read/open timeout in seconds for Ollama requests (default **120**; use `ask --timeout` / `-t` to override per run) |
| `OLLAMA_AGENT_PARSE_TOOL_JSON` | Set to `1` to run tools parsed from JSON lines in assistant text (fallback when the model does not emit native tool calls) |
| `NO_COLOR` | Set (any value) to disable ANSI colors (see [no-color.org](https://no-color.org/)) |
| `OLLAMA_AGENT_COLOR` | Set to `0` to disable colors even on a TTY |
| `OLLAMA_AGENT_MARKDOWN` | Set to `0` to disable Markdown formatting of assistant replies (plain text only) |

## Troubleshooting

- **Use a tool-capable model** — Set `OLLAMA_AGENT_MODEL` to a model that supports function/tool calling (e.g. a recent coder-tuned variant). If the model only prints `{"name": "read_file", ...}` in plain text, tools never run unless you enable `OLLAMA_AGENT_PARSE_TOOL_JSON=1`.
- **Malformed diffs** — Headers must look like `git diff`: `--- a/file` then `+++ b/file` then a unified hunk line starting with `@@` (not legacy `--- N,M ----`). Do not put commas after path tokens. The gem normalizes some mistakes and runs `patch --dry-run` before applying.
- **Request timeouts** — The agent defaults to a **120s** HTTP timeout (longer than ollama-client’s 30s). If you still hit `Ollama::TimeoutError`, raise it with `OLLAMA_AGENT_TIMEOUT=300`, `bundle exec ruby exe/ollama_agent ask --timeout 300 "..."`, or `-t 300`. Ensure the variable name is exactly `OLLAMA_AGENT_TIMEOUT` (a leading typo such as `vOLLAMA_AGENT_TIMEOUT` is ignored).

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

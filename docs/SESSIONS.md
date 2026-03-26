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

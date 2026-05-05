# Contributing

## Tests

- Run **`bundle exec rspec`** before opening a PR.
- Prefer **behavior-focused** examples; stub external binaries (`patch`, `rg`) when asserting failure paths.
- Add or extend specs when you change the agent loop, tool schemas, sandbox, or budget/loop detection.

## Style

- Run **`bundle exec rubocop`**. The repository is moving toward a clean full-tree baseline; CI currently runs RuboCop with **`continue-on-error: true`** until legacy offenses are cleared.
- Add **`# frozen_string_literal: true`** to new Ruby files.

## Error handling

- Do **not** use **`rescue Exception`** (it catches `Interrupt` / `SignalException`). Rescue **`StandardError`** (or narrower types) and either re-raise, wrap in **`OllamaAgent::Error`**, or log and return a safe value—never swallow signals.

## Architecture notes

- **Tools:** Prefer **`OllamaAgent::Tools::BuiltInSchemas.register`** for new first-party tool schemas instead of hard-coding branches in unrelated modules.
- **Logging:** Use the agent’s **`Logger`** (or `OllamaAgent::Agent`’s `logger` reader) instead of bare **`warn`** for user-relevant messages so embedders can stub or redirect output.

Thank you for helping improve `ollama_agent`.

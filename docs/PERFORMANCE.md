# Performance notes

This document records **known costs** and **when to optimize**. No changes here are mandatory for typical CLI use.

## Text search (`search_code`, text mode)

Each call spawns **`rg`** or **`grep`** as a subprocess. For very chatty agents or huge trees, that overhead can dominate. Before changing behavior:

1. Measure wall time for your workload (local disk vs network FS matters).
2. Consider narrowing `directory`, or using Ruby index modes (`mode: method`, etc.) which avoid ripgrep for symbol queries.

## Patch application (`edit_file`)

The flow runs **`patch --dry-run`** before apply when validation passes, then **`patch`** again on success—two processes per confirmed edit. Caching or reusing dry-run output would save one spawn but adds complexity; only pursue if profiling shows it matters.

## Full-file reads

`read_file` without line range loads the whole file (subject to `OLLAMA_AGENT_MAX_READ_FILE_BYTES`). Prefer `start_line` / `end_line` for large logs.

## Context trimming (`Context::Manager#trim`)

Each trim pass keeps a parallel array of per-message token estimates so the sliding-window loop does not re-scan message bodies on every `over_budget?` check. If you change trimming strategy, profile long sessions with a tight `max_tokens` budget before adding further caching.

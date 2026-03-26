---
name: self-improvement-sandbox-safety
description: >
  Guardrails for `ollama_agent improve --mode automated` sandbox safety: minimal diffs, build-file restoration, patch validation, and safe merge rules.
---

# Skill: Self-Improvement Sandbox Safety

Use this skill when the agent is asked to run or design improvements using the gem’s self-improvement flow, especially:

- `ollama_agent self_review --mode automated`
- `ollama_agent improve --mode automated --apply`

This skill is about preventing “test succeeded in sandbox but tree broke” failures and preventing the model from taking risky actions in the live repo.

## Non-negotiable invariants

### 1) Keep build-critical files intact (or restore them)
- Do not delete or corrupt `Gemfile`, `Gemfile.lock`, `*.gemspec`, `exe/`, or `.ruby-version` in the sandbox.
- Assume the model may still break these during `edit_file`.
- The system should restore build essentials before running tests. Still, avoid “creative” patching of those files.

### 2) Run tests inside the sandbox
- Always run `bundle exec rspec` with the working directory set to the sandbox root.
- Ensure bundler points at the sandbox `Gemfile` (via `BUNDLE_GEMFILE`).

### 3) Require valid unified diffs
When producing an `edit_file` patch:
- Include `--- a/<path>` and `+++ b/<path>` headers.
- Use the correct ordering: `---` then `+++` then `@@ -x,y +x,y @@` hunk headers.
- Ensure the hunk `@@` line counts match the changed block exactly.
- Avoid legacy context-diff hunks like `--- N,M ----`.
- Prefer minimal, local hunks: one logical change per hunk.

### 4) Avoid merging ignored test artifacts
With `--apply`:
- Merge only actual source changes.
- Never merge files that should be treated as artifacts, caches, or status trackers created during test runs (e.g. `.rspec_status`).
- If the sandbox contains ignored test artifacts, skip them during merge.

## Minimal-diff strategy (to avoid fragile mega-patches)

Required behavior for `--mode automated`:
- Keep each `edit_file` patch small.
- Do not replace whole methods unless the patch is tiny and context is exact.
- Do not replace multi-hundred-line hunks.
- Prefer a sequence:
  - add a helper (small)
  - update one call site (small)
  - add/adjust one focused spec (small)

## “Patch checklist” before edit_file

Before generating a patch, verify:
- The target path in the patch (`+++ b/...`) matches the file you’re editing.
- The patch contains at least one `@@ ... @@` hunk header.
- The diff hunk order is correct (first `+++ ...` must appear before the first `@@`).
- The patch contains the exact surrounding context lines expected by the dry-run validator.

## Prompt addendum snippet (to include in FIX_PROMPT)

If you need to extend an existing FIX_PROMPT, add something like:

Minimal diffs only: fewest lines per edit_file, exact @@ counts—no whole-method or mega-hunks. Never delete build-critical files (Gemfile, Gemfile.lock, *.gemspec, exe/) and rely on restore before tests. With --apply, never merge ignored test artifacts (e.g. .rspec_status).


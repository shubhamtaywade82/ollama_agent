---
name: code-review
description: Structured code review for Ruby/Rails projects. Detects file type, scans the local codebase for project-specific patterns first, then applies global skills in priority order. Use when asked to review, audit, or check code quality.
disable-model-invocation: true
argument-hint: [file-or-directory]
allowed-tools: Read, Glob, Grep
---

# Code Review — Orchestrator

Perform a structured code review of `$ARGUMENTS`. Follow this exact workflow.

## Step 1 — Identify File Type

| File Pattern | Type | Primary Skills |
|---|---|---|
| `app/controllers/**` | Controller | rails-best-practices, solid-ruby |
| `app/models/**` | Model | rails-best-practices, solid-ruby, ruby-design-patterns |
| `app/services/**` | Service Object | solid-ruby, rails-best-practices |
| `app/workers/**`, `app/jobs/**` | Background Job | rails-best-practices, solid-ruby |
| `spec/**/*_spec.rb` | RSpec spec | rspec, solid-ruby |
| `db/migrate/**` | Migration | rails-best-practices |
| `config/routes.rb` | Routes | rails-best-practices |
| `app/views/**` | View/Partial | rails-best-practices, ruby-style |
| `lib/**` | Library | solid-ruby, ruby-style, ruby-design-patterns |

## Step 2 — Scan Project for Existing Patterns (MANDATORY)

Before applying any rule, read 2–3 similar files in the same directory to extract project conventions.

**Find and extract:**
- Controllers: response format, base controller, auth pattern, error format, param naming
- Models: shared concerns/modules, validation style, enum convention, scope naming
- Services: calling convention (`.call` vs `.run`), return type, class naming, base class
- Specs: factory style, shared examples, helper includes, context naming

See [project-pattern-detection.md](project-pattern-detection.md) for full detection checklist.

## Step 3 — Review in Priority Order

### 🔴 CRITICAL — Always flag, regardless of project style
- SQL injection via string interpolation
- Missing Strong Parameters / mass assignment vulnerability
- `rescue Exception` (swallows signals)
- User input in file paths, shell commands, or redirects
- Hardcoded credentials or secrets
- `save` return value silently ignored
- Auth check missing or bypassable
- Sensitive data logged

### 🟠 PERFORMANCE — Always flag
- N+1 queries (association in loop without preload)
- `.where` / query methods in AR instance methods (breaks preloading)
- `.count` where `.size` should be used
- `any?`/`empty?` then `.each` on same relation (two queries)
- `exists?` called multiple times (never memoized)
- `find_each` missing on large dataset iteration
- No timeout on external HTTP/Redis calls
- `after_save` for side effects instead of `after_commit`

### 🟡 PROJECT CONSISTENCY — Most important correctness layer
Compare against patterns found in Step 2. Phrase as: "The rest of the codebase does X — this does Y."
- Different service calling convention
- Different response/error format in controller
- Different factory/spec helper pattern
- Missing shared concern/module that all similar models include
- Different enum/scope/validation naming

### 🔵 BEST PRACTICES — Apply where no project pattern covers
Reference: rails-best-practices, solid-ruby, rspec, ruby-design-patterns

### ⚪ STYLE — Only if clearly inconsistent
Reference: ruby-style, rails-style

## Step 4 — Output Format

```
## Code Review: [filename]
**Type:** [file type]
**Project patterns detected:** [1-line summary]

### 🔴 CRITICAL | [title]
**File:** path/to/file.rb:42
**Issue:** [what and why]
**Fix:**
# Before / After code
**Rule:** [source]

[repeat per finding, skip empty severity sections]

---
## Verdict: SHIP ✅ | NEEDS FIXES 🔧 | CRITICAL ISSUES 🚨

- 🔴 Critical: N
- 🟠 Performance: N
- 🟡 Consistency: N
- 🔵 Best Practice: N
- ⚪ Style: N

Must fix before merge: [list]
Can fix in follow-up: [list]
```

After verdict, ask: "Want me to apply the fixes?"

## Behavior Rules
- Cannot find similar files → say so, proceed with global skills only
- Do not flag style as critical
- Do not invent violations — only flag what is visible in the code
- Project patterns beat global skills when they conflict
- One finding per issue — no duplicates across severity levels
- For specs: also check that the spec tests what production code actually does

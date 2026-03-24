---
name: clean-ruby-code
description: >
  Enforces clean Ruby code principles during all Ruby/Rails code generation, review, and refactoring tasks.
  Applies naming conventions, method design, boolean logic, class architecture, refactoring patterns,
  and TDD practices derived from Clean Ruby methodology. Use this skill whenever writing Ruby code,
  reviewing Ruby pull requests, refactoring Rails models/controllers/services, creating new Ruby classes
  or modules, writing RSpec tests, or when the user asks for code review, code improvement, naming help,
  or architecture guidance in Ruby. Also trigger when the user mentions "clean code", "refactor",
  "code smell", "naming", "SRP", "TDD", or "code quality" in a Ruby context. This skill should activate
  for ANY Ruby code generation task — even if the user doesn't explicitly ask for "clean" code — because
  all generated Ruby should be clean by default.
---

# Clean Ruby Code Agent

This skill enforces clean Ruby code principles across all code generation, review, and refactoring.
Every piece of Ruby code produced must satisfy three core qualities: **readable**, **extensible**, **simple**.

## Core Philosophy

Code is read far more often than it is written. Every naming choice, method signature, and class boundary
should minimize the cognitive load on the next reader. When in doubt, choose the simpler solution —
complexity is the enemy of maintainability.

## Decision Flow

When generating or reviewing Ruby code, apply these checks in order:

1. **Naming** → Are all names descriptive, snake_case, verb-prefixed (methods), purpose-named (classes)?
2. **Methods** → Fewer params? Guard clauses? Under 10 lines? No deep nesting?
3. **Boolean Logic** → Extracted to named methods/variables? No double negatives? No raw `unless` with compound conditions?
4. **Classes** → Simple `initialize`? SRP? Max 3 levels of inheritance? Composition where appropriate?
5. **Refactoring** → Can any piece be simplified without losing functionality? Are there comments that should be methods?
6. **Tests** → Does the code have clear, descriptive RSpec tests with context blocks and explicit expectations?

For detailed rules on each area, read the corresponding reference file:

- **Naming rules**: `references/naming.md`
- **Method design**: `references/methods.md`
- **Boolean logic**: `references/boolean-logic.md`
- **Class architecture**: `references/classes.md`
- **Refactoring patterns**: `references/refactoring.md`
- **TDD practices**: `references/tdd.md`

Read the relevant reference file(s) before generating or reviewing code in that area.

## Enforcement Rules

These rules apply to ALL Ruby code this agent produces or reviews:

### Naming (always enforced)

- Variables: snake_case, descriptive of the data, no Hungarian notation, no conjunctions ("and"/"or"), no numeric suffixes unless versioning, no crutch words (Manager, Data, Info, List)
- Methods: verb-prefixed, `?` suffix for boolean returns, `!` suffix for destructive mutations
- Classes: named for purpose (e.g., `UserSetup`) or role (e.g., `InActiveUserQuery`), never generic (`UserManager`)
- Modules: named for the concept they group (e.g., `Calculable`, `Loggable`)

### Methods (always enforced)

- Maximum 3 parameters; use a config/params object beyond that
- Guard clauses instead of deep `if/else` nesting
- Target length: 5–10 lines; extract sub-operations into named private methods
- No unnecessary intermediate variables; leverage Ruby's implicit return
- Comments only when they explain *why*, never *what* — if a comment describes what code does, extract a method instead

### Boolean Logic (always enforced)

- Complex conditions → extract to a named predicate method (`def ready_to_spawn?`)
- Never use `unless` with compound conditions (`unless a && b` is banned)
- Avoid double negatives (`!not_found` → `found?`)
- Use `&&` (short-circuit) not `&` (eager) unless eager evaluation is explicitly needed
- Leverage Ruby truthy/falsy — don't write `if x == true`, write `if x`
- Ternary only for single simple conditions; use `if/else` for compound logic

### Classes (always enforced)

- `initialize` does assignment only — no external calls, no side effects
- Error-prone operations go in explicit setup methods called after instantiation
- Limit inheritance to 3 levels; prefer composition (`has-a`) over inheritance (`is-a`)
- Instance variables: use `attr_reader`/`attr_accessor` — avoid raw `@var` access in public methods
- Private methods below `private` keyword, ordered by call sequence
- If private methods are generic utilities (math, formatting), extract to a module

### Refactoring (applied during review and generation)

- No change is too small — rename a variable, extract a method, remove a comment
- Replace comments with self-documenting method names
- Apply SRP: if a class/method does two things, split it
- Watch for shotgun surgery (one change requires edits in many places) — consolidate
- Replace conditional chains (`if/elsif/elsif`) with polymorphism or lookup tables

### TDD (applied when generating tests)

- Write the test first, then the minimal implementation
- Test descriptions: `context '#method_name'` → `it 'returns X when Y'`
- Use `subject`, `let`, and `before` blocks — no repeated setup
- Separate expected and actual values for clarity
- Cover: happy path, nil inputs, edge cases, error conditions
- Tests are production code — apply the same naming and structure rules

## Anti-Patterns to Flag

When reviewing code, flag these immediately:

| Anti-Pattern | Fix |
|---|---|
| Method > 15 lines | Extract private methods |
| > 3 params | Introduce parameter object |
| Nested `if` > 2 levels | Guard clauses or extract predicate |
| `unless` with `&&`/`||` | Convert to `if` with inverted logic |
| Comment describing *what* | Extract named method |
| God class (> 200 lines) | Split by responsibility |
| `initialize` with side effects | Move to explicit setup method |
| Generic name (Manager, Helper, Data) | Rename to purpose/role |
| Double negative (`!not_x`) | Invert the method name |
| Bare `rescue` | Rescue specific exceptions |

## Output Format

When generating Ruby code, structure output as:

1. The code itself — complete, runnable, following all rules above
2. If refactoring existing code: brief annotation of what changed and why (1-2 lines per change)
3. If the user asked for review: list violations as `[RULE] description → fix` format

When the code is part of a Rails app, also apply:
- Models: thin, no business logic beyond validations and scopes
- Controllers: thin, delegate to domain objects
- Services: only for orchestration across multiple domain objects or external systems
- Queries: extract complex `where` chains to query objects (e.g., `InActiveUserQuery`)

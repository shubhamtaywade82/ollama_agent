# Interactive Completion System (AI Runtime Shell) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the AI Runtime Shell interactive completion UX — proper menu erase/redraw, ESC to close, char-input closes menu, navigation redraws, palette memoization, richer suggestion display.

**Architecture:** The `RuntimeCommandSystem` backend (registry, suggestion engine, ghost text, AST, completers) is already fully implemented. This plan fixes the TUI rendering layer: `TuiSlashReader#read_line` needs menu erase-before-redraw using ANSI cursor save/restore, and `ReplShared#runtime_command_palette` needs memoization. All new drawing uses `cursor.save`/`cursor.restore` (TTY::Cursor) so the menu renders below the input line without corrupting cursor state.

**Tech Stack:** Ruby, `tty-reader`, `tty-cursor` (via tty-reader), RSpec

---

## File Map

| File | Change |
|------|--------|
| `lib/ollama_agent/tui_slash_reader.rb` | Add `erase_completion_menu`, `draw_menu_items`; fix `show_completion_menu`; add ESC + char-close + auto-redraw in `read_line` |
| `lib/ollama_agent/runtime_command_system/suggestion.rb` | Update `display_text` to show capability badges aligned |
| `lib/ollama_agent/cli/repl_shared.rb` | Memoize `runtime_command_palette` |
| `spec/ollama_agent/tui_slash_reader_spec.rb` | New tests for erase/draw helpers, ESC close, char close |
| `spec/ollama_agent/runtime_command_system/suggestion_spec.rb` (new) | Tests for `display_text` formatting |

---

## Task 1: Memoize CommandPalette in ReplShared

**Files:**
- Modify: `lib/ollama_agent/cli/repl_shared.rb`

`runtime_command_palette` currently creates a new `CommandPalette` on every `read_user_line` call (and thus every keystroke session). Memoize it.

- [ ] **Step 1: Write the failing test**

Create `spec/ollama_agent/cli/repl_shared_palette_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/cli/repl_shared"
require "ollama_agent/runtime_command_system/command_palette"

RSpec.describe "ReplShared#runtime_command_palette" do
  let(:test_class) do
    Class.new do
      include OllamaAgent::CLI::ReplShared

      def initialize(agent)
        @agent = agent
        @stdout = StringIO.new
      end

      public :runtime_command_palette
    end
  end

  let(:agent) { instance_double(OllamaAgent::Agent, model: "qwen3:32b") }
  subject(:obj) { test_class.new(agent) }

  before do
    allow(OllamaAgent::Plugins::Registry).to receive(:all_command_handlers).and_return([])
  end

  it "returns the same instance across multiple calls" do
    first  = obj.runtime_command_palette
    second = obj.runtime_command_palette

    expect(first).to be(second)
  end

  it "returns a CommandPalette" do
    expect(obj.runtime_command_palette).to be_a(OllamaAgent::RuntimeCommandSystem::CommandPalette)
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
bundle exec rspec spec/ollama_agent/cli/repl_shared_palette_spec.rb -f doc
```

Expected: FAIL — `returns the same instance` fails because two separate objects are returned.

- [ ] **Step 3: Memoize the palette**

In `lib/ollama_agent/cli/repl_shared.rb`, change:

```ruby
def runtime_command_palette
  require_relative "../runtime_command_system/command_palette"

  commands = SLASH_COMMANDS.merge(plugin_slash_command_strings.to_h { |cmd| [cmd, "Plugin command"] })
  OllamaAgent::RuntimeCommandSystem::CommandPalette.new(
    commands: commands,
    session: { agent: @agent }
  )
end
```

To:

```ruby
def runtime_command_palette
  require_relative "../runtime_command_system/command_palette"

  @runtime_command_palette ||= begin
    commands = SLASH_COMMANDS.merge(plugin_slash_command_strings.to_h { |cmd| [cmd, "Plugin command"] })
    OllamaAgent::RuntimeCommandSystem::CommandPalette.new(
      commands: commands,
      session: { agent: @agent }
    )
  end
end
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
bundle exec rspec spec/ollama_agent/cli/repl_shared_palette_spec.rb -f doc
```

Expected: PASS — both examples green.

- [ ] **Step 5: Run full suite to confirm no regressions**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/ spec/ollama_agent/tui_slash_reader_spec.rb -f progress
```

Expected: 8 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/ollama_agent/cli/repl_shared.rb spec/ollama_agent/cli/repl_shared_palette_spec.rb
git commit -m "perf: memoize runtime_command_palette to avoid recreation per keystroke session"
```

---

## Task 2: Richer Suggestion display_text

**Files:**
- Modify: `lib/ollama_agent/runtime_command_system/suggestion.rb`
- Create: `spec/ollama_agent/runtime_command_system/suggestion_spec.rb`

Current `display_text` packs description + capabilities together with no alignment. Goal: fixed-width name column, description, then capability badges like `[tools]`.

- [ ] **Step 1: Write failing tests**

Create `spec/ollama_agent/runtime_command_system/suggestion_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/runtime_command_system/suggestion"

RSpec.describe OllamaAgent::RuntimeCommandSystem::Suggestion do
  describe "#display_text" do
    it "shows text only when no description and no capabilities" do
      s = described_class.new(text: "/help", type: :command)
      expect(s.display_text).to eq("/help")
    end

    it "shows text and description with padding when no capabilities" do
      s = described_class.new(text: "/model", type: :command, description: "Switch model")
      expect(s.display_text).to include("/model")
      expect(s.display_text).to include("Switch model")
    end

    it "shows capability badges in brackets after description" do
      s = described_class.new(
        text: "qwen3:32b",
        type: :model,
        description: "local • 32k • loaded",
        capabilities: %i[tools]
      )
      text = s.display_text
      expect(text).to include("qwen3:32b")
      expect(text).to include("local • 32k • loaded")
      expect(text).to include("[tools]")
    end

    it "shows multiple capability badges space-separated" do
      s = described_class.new(
        text: "gemma3",
        type: :model,
        description: "local",
        capabilities: %i[vision reasoning]
      )
      expect(s.display_text).to include("[vision]")
      expect(s.display_text).to include("[reasoning]")
    end

    it "aligns to 30-char name column" do
      s = described_class.new(
        text: "qwen3:32b",
        type: :model,
        description: "local • 32k",
        capabilities: %i[tools]
      )
      # name column is left-padded to 30 chars
      expect(s.display_text).to start_with("qwen3:32b".ljust(30))
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/suggestion_spec.rb -f doc
```

Expected: FAIL on alignment test (current format does not use `ljust(30)`).

- [ ] **Step 3: Update display_text**

In `lib/ollama_agent/runtime_command_system/suggestion.rb`, replace `display_text`:

```ruby
def display_text
  name_col = text.ljust(30)
  details = []
  details << description if description && !description.empty?
  badge_str = capabilities.map { |c| "[#{c}]" }.join(" ")
  return name_col.rstrip if details.empty? && badge_str.empty?

  suffix = details.empty? ? badge_str : "#{details.join(" ")}  #{badge_str}".rstrip
  "#{name_col}#{suffix}"
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/suggestion_spec.rb -f doc
```

Expected: 5 examples, 0 failures.

- [ ] **Step 5: Run existing palette spec to confirm no regression**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/ -f progress
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/ollama_agent/runtime_command_system/suggestion.rb \
        spec/ollama_agent/runtime_command_system/suggestion_spec.rb
git commit -m "feat: align Suggestion display_text to 30-char name column with capability badges"
```

---

## Task 3: Add menu erase/draw helpers to TuiSlashReader

**Files:**
- Modify: `lib/ollama_agent/tui_slash_reader.rb`

Add two private helpers: `erase_completion_menu` (clears menu lines below input using cursor save/restore) and `draw_menu_items` (draws suggestions below input using cursor save/restore). Both are side-effect only (ANSI output, update `@menu_lines_printed`). `show_completion_menu` refactored to call them.

The strategy: cursor save (`\e[s`) saves absolute cursor position. We print below, then restore. This means menu renders below input without disturbing cursor state.

- [ ] **Step 1: Write tests for helpers**

Add to `spec/ollama_agent/tui_slash_reader_spec.rb`:

```ruby
describe "menu draw/erase helpers" do
  let(:out) { StringIO.new }

  def make_reader
    described_class.new(
      completion_candidates: [],
      input: StringIO.new,
      output: out
    )
  end

  it "erase_completion_menu is a no-op when menu_lines_printed is zero" do
    reader = make_reader
    reader.instance_variable_set(:@menu_lines_printed, 0)
    reader.send(:erase_completion_menu)
    expect(out.string).to be_empty
  end

  it "erase_completion_menu emits cursor-save, N erase sequences, cursor-restore" do
    reader = make_reader
    reader.instance_variable_set(:@menu_lines_printed, 2)
    reader.send(:erase_completion_menu)

    output = out.string
    expect(output).to include("\e[s")   # cursor save
    expect(output).to include("\e[u")   # cursor restore
    expect(output).to include("\e[2K")  # clear line (at least once)
    expect(reader.instance_variable_get(:@menu_lines_printed)).to eq(0)
  end

  it "draw_menu_items emits nothing when suggestions list is empty" do
    reader = make_reader
    palette = instance_double(OllamaAgent::RuntimeCommandSystem::CommandPalette)
    menu = OllamaAgent::RuntimeCommandSystem::InteractiveMenu.new
    allow(palette).to receive(:menu).and_return(menu)
    reader.instance_variable_set(:@command_palette, palette)
    reader.send(:draw_menu_items)
    expect(out.string).to be_empty
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bundle exec rspec spec/ollama_agent/tui_slash_reader_spec.rb -f doc
```

Expected: FAIL — `erase_completion_menu` and `draw_menu_items` don't exist yet.

- [ ] **Step 3: Add @menu_lines_printed init and the two helpers**

In `lib/ollama_agent/tui_slash_reader.rb`, inside `TuiSlashReader`, add after `attr_accessor :completion_candidates, :command_palette`:

```ruby
def initialize(completion_candidates:, **)
  super(**)
  @completion_candidates = Array(completion_candidates).uniq.sort
  @menu_lines_printed = 0
end
```

Then add these private methods at the end of the private section:

```ruby
def erase_completion_menu
  return if @menu_lines_printed.nil? || @menu_lines_printed.zero?

  output.print(cursor.save)
  @menu_lines_printed.times do
    output.print(cursor.down(1))
    output.print(cursor.clear_line)
  end
  output.print(cursor.restore)
  @menu_lines_printed = 0
end

def draw_menu_items
  return unless completion_menu_visible?

  items = @command_palette.menu.suggestions.first(8)
  return if items.empty?

  output.print(cursor.save)
  items.each_with_index do |suggestion, i|
    output.print(cursor.down(1))
    output.print(cursor.clear_line)
    marker = i == @command_palette.menu.index ? "\e[32m›\e[0m" : " "
    output.print("  #{marker} #{suggestion.display_text}")
  end
  output.print(cursor.restore)
  @menu_lines_printed = items.length
end
```

- [ ] **Step 4: Refactor show_completion_menu to use the helpers**

Replace the existing `show_completion_menu` private method:

```ruby
def show_completion_menu(text, suggestions = nil)
  suggestions ||= @command_palette.suggestions(text)
  @command_palette.menu.show(suggestions)
  return if suggestions.empty?

  output.puts
  suggestions.first(8).each_with_index do |suggestion, index|
    marker = index == @command_palette.menu.index ? "›" : " "
    output.puts "  #{marker} #{suggestion.display_text}"
  end
end
```

With:

```ruby
def show_completion_menu(text, suggestions = nil)
  suggestions ||= @command_palette.suggestions(text)
  @command_palette.menu.show(suggestions)
  draw_menu_items
end
```

- [ ] **Step 5: Add close_completion_menu helper**

After `erase_completion_menu`, add:

```ruby
def close_completion_menu
  erase_completion_menu
  @command_palette&.menu&.hide
end
```

- [ ] **Step 6: Run tests to confirm they pass**

```bash
bundle exec rspec spec/ollama_agent/tui_slash_reader_spec.rb -f doc
```

Expected: all existing + new tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/ollama_agent/tui_slash_reader.rb spec/ollama_agent/tui_slash_reader_spec.rb
git commit -m "feat: add erase/draw menu helpers with ANSI cursor save-restore to TuiSlashReader"
```

---

## Task 4: Fix read_line — ESC closes menu, char closes menu, auto-redraw

**Files:**
- Modify: `lib/ollama_agent/tui_slash_reader.rb`

The `read_line` loop needs three changes:
1. **ESC** key: close menu
2. **Regular char typed while menu visible**: close menu before inserting char
3. **Auto-redraw**: after reprinting input at end of each iteration, redraw menu if still visible
4. **Erase stale menu**: at top of each iteration before `clear_display`

- [ ] **Step 1: Write tests for ESC and char-close behavior**

Add to `spec/ollama_agent/tui_slash_reader_spec.rb`:

```ruby
describe "close_completion_menu" do
  it "hides the menu state and resets menu_lines_printed" do
    out = StringIO.new
    reader = described_class.new(
      completion_candidates: [],
      input: StringIO.new,
      output: out
    )
    palette = instance_double(OllamaAgent::RuntimeCommandSystem::CommandPalette)
    menu = OllamaAgent::RuntimeCommandSystem::InteractiveMenu.new
    menu.show([
      OllamaAgent::RuntimeCommandSystem::Suggestion.new(text: "/model", type: :command)
    ])
    allow(palette).to receive(:menu).and_return(menu)
    reader.instance_variable_set(:@command_palette, palette)
    reader.instance_variable_set(:@menu_lines_printed, 3)

    reader.send(:close_completion_menu)

    expect(menu.visible?).to be false
    expect(reader.instance_variable_get(:@menu_lines_printed)).to eq(0)
  end
end
```

- [ ] **Step 2: Run test to confirm it passes (close_completion_menu already added in Task 3)**

```bash
bundle exec rspec spec/ollama_agent/tui_slash_reader_spec.rb -f doc
```

Expected: new `close_completion_menu` test passes.

- [ ] **Step 3: Add ESC handler in read_line**

In `read_line`, locate the UP key handler block. Before it (in the same if/elsif chain), add:

```ruby
elsif console.keys[char] == :escape
  close_completion_menu if command_palette_active_for?(line.text)
```

The `escape` key symbol is recognized by tty-reader for ESC sequences. Add this BEFORE the `:up` handler:

```ruby
elsif console.keys[char] == :escape
  close_completion_menu if command_palette_active_for?(line.text)
elsif console.keys[char] == :up
  # existing up handler ...
```

- [ ] **Step 4: Close menu on regular char input while menu visible**

In `read_line`, find the `else` branch that handles regular characters (after all special key handlers):

```ruby
else
  if raw && code == CARRIAGE_RETURN
    char = "\n"
    line.move_to_end
  end
  line.insert(char)
  buffer = line.text
end
```

Change to close menu before inserting:

```ruby
else
  if raw && code == CARRIAGE_RETURN
    char = "\n"
    line.move_to_end
  end
  close_completion_menu if completion_menu_visible? && code != CARRIAGE_RETURN && code != NEWLINE
  line.insert(char)
  buffer = line.text
end
```

- [ ] **Step 5: Erase stale menu at top of each iteration and auto-redraw at bottom**

At the top of the while loop body, BEFORE `clear_display`, add:

```ruby
erase_completion_menu if raw && echo && completion_menu_visible?

clear_display(line, screen_width) if raw && echo
```

At the BOTTOM of the reprint section (inside `if raw && echo`), AFTER ghost text and cursor positioning, add the auto-redraw:

Locate this block:

```ruby
if raw && echo
  output.print(line.to_s)
  ghost = current_ghost_for(line)
  if ghost && line.end?
    output.print("\e[2m#{ghost.suffix}\e[0m")
    output.print(cursor.backward(ghost.suffix.length))
  end
  if char == "\n"
    line.move_to_start
  elsif !line.end?
    output.print(cursor.backward(line.text_size - line.cursor))
  end
end
```

Change to:

```ruby
if raw && echo
  output.print(line.to_s)
  ghost = current_ghost_for(line)
  if ghost && line.end?
    output.print("\e[2m#{ghost.suffix}\e[0m")
    output.print(cursor.backward(ghost.suffix.length))
  end
  if char == "\n"
    line.move_to_start
  elsif !line.end?
    output.print(cursor.backward(line.text_size - line.cursor))
  end
  draw_menu_items if completion_menu_visible?
end
```

- [ ] **Step 6: Fix UP navigation to navigate AND trigger redraw**

Current UP handler:

```ruby
elsif console.keys[char] == :up
  if completion_menu_visible?
    apply_selected_suggestion!(line, @command_palette.menu.previous)
    buffer = line.text
  elsif history_previous?
    line.replace(mutable_copy(history_previous))
  end
```

The `draw_menu_items` call added in Step 5 will auto-redraw at end of iteration. But `menu.previous` was already called, so `@command_palette.menu.index` is updated. The auto-redraw in Step 5 will use the new index. No additional change needed here — `draw_menu_items` fires at end of each iteration when `completion_menu_visible?`.

Verify: the DOWN handler opens the menu and navigates to next. After `menu.next` updates index, `draw_menu_items` redraws with new selection at end of iteration.

Existing DOWN handler:

```ruby
elsif console.keys[char] == :down
  if command_palette_active_for?(line.text)
    show_completion_menu(line.text) unless completion_menu_visible?
    apply_selected_suggestion!(line, @command_palette.menu.next)
    buffer = line.text
  elsif track_history?
    line.replace(mutable_copy(history_next? ? history_next : buffer))
  end
```

Note: `show_completion_menu` calls `menu.show` (resets index to 0) then `draw_menu_items`. But immediately after, `menu.next` is called. Then at end of iteration `draw_menu_items` fires AGAIN with the updated index. The first draw (from `show_completion_menu`) shows index=0; the second draw (auto-redraw) shows index=1 after `menu.next`. This causes double-draw.

Fix: remove `draw_menu_items` from `show_completion_menu` since auto-redraw handles it:

```ruby
def show_completion_menu(text, suggestions = nil)
  suggestions ||= @command_palette.suggestions(text)
  @command_palette.menu.show(suggestions)
  # draw_menu_items removed — auto-redraw at end of read_line iteration handles it
end
```

- [ ] **Step 7: Run full spec suite**

```bash
bundle exec rspec spec/ollama_agent/runtime_command_system/ spec/ollama_agent/tui_slash_reader_spec.rb -f progress
```

Expected: all green.

- [ ] **Step 8: Commit**

```bash
git add lib/ollama_agent/tui_slash_reader.rb spec/ollama_agent/tui_slash_reader_spec.rb
git commit -m "feat: fix interactive menu — ESC closes, chars close, auto-redraws on navigation"
```

---

## Task 5: Run and verify end-to-end

**Files:** none (verification only)

- [ ] **Step 1: Run full spec suite**

```bash
bundle exec rspec --format progress
```

Expected: all examples pass, 0 failures.

- [ ] **Step 2: Start TUI and manually test completion flow**

```bash
bundle exec ollama_agent tui
```

Test sequence:
1. Type `/mod` → ghost text `el` appears dimmed after cursor
2. Press TAB → accepts ghost, input becomes `/model `
3. Type `qw` → ghost text `en3:32b` appears
4. Press DOWN → dropdown appears below input with `›` on first item
5. Press DOWN again → `›` moves to second item
6. Press UP → `›` moves back to first item
7. Press ENTER → selected model text fills input
8. Type `/mod` again, press DOWN → dropdown opens
9. Press ESC → dropdown disappears, input unchanged
10. Type `/model q`, press DOWN → dropdown opens; type a char → dropdown closes

- [ ] **Step 3: Confirm ghost text still works correctly**

Type `/mod` — confirm ghost text renders, TAB accepts it, backspace removes ghost.

- [ ] **Step 4: Commit (if any fixup changes needed)**

```bash
git add -p
git commit -m "fix: address manual verification findings from completion system smoke test"
```

---

## Self-Review

**Spec coverage check:**
- Ghost text (already existing, unchanged) ✅
- TAB accepts ghost (already working, unchanged) ✅
- CommandRegistry (already existing, unchanged) ✅
- SuggestionEngine (already existing, unchanged) ✅
- ModelCompleter / ProviderCompleter (already existing, unchanged) ✅
- CommandPalette memoization → Task 1 ✅
- Richer display_text with capability badges → Task 2 ✅
- Menu erase + draw with cursor save/restore → Task 3 ✅
- ESC closes menu → Task 4 Step 3 ✅
- Char closes menu → Task 4 Step 4 ✅
- Auto-redraw after navigation → Task 4 Step 5-6 ✅
- End-to-end smoke test → Task 5 ✅

**Placeholder scan:** None found. All steps include exact code.

**Type consistency:**
- `cursor.save` / `cursor.restore` / `cursor.down(1)` / `cursor.clear_line` — all from `TTY::Cursor` module, available in `TuiSlashReader` (inherits from `TTY::Reader` which exposes `cursor`)
- `@menu_lines_printed` initialized in `initialize`, used in `erase_completion_menu` and `draw_menu_items`
- `completion_menu_visible?` — existing method, returns `@command_palette&.menu&.visible?`
- `close_completion_menu` — defined in Task 3, used in Task 4

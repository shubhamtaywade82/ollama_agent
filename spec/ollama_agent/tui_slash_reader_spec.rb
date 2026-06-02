# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/ollama_agent/tui_slash_reader"

RSpec.describe OllamaAgent::TuiSlashReader do
  describe OllamaAgent::SlashCompletion do
    describe ".longest_common_prefix" do
      it "returns the shared prefix" do
        expect(described_class.longest_common_prefix(%w[/model /models])).to eq("/model")
      end

      it "returns empty for an empty list" do
        expect(described_class.longest_common_prefix([])).to eq("")
      end
    end
  end

  describe "tab completion" do
    it "uses a mutable buffer when the candidate is frozen so backspace does not raise" do
      reader = described_class.new(
        completion_candidates: ["/help"],
        input: StringIO.new,
        output: StringIO.new
      )
      line = TTY::Reader::Line.new("/h")
      reader.send(:apply_slash_tab!, line, "\t")

      expect(line.text).to eq("/help")
      expect(line.text).not_to be_frozen
      expect do
        line.left
        line.delete
      end.not_to raise_error
    end
  end

  describe "close_completion_menu integration" do
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

    it "erase_completion_menu emits cursor-save, N down+clear sequences, cursor-restore" do
      reader = make_reader
      reader.instance_variable_set(:@menu_lines_printed, 2)
      reader.send(:erase_completion_menu)

      output = out.string
      # TTY::Cursor uses DEC save/restore (\e7/\e8) or ANSI (\e[s/\e[u) depending on platform;
      # accept either variant so the test is not tied to a specific terminal emulator.
      expect(output).to match(/\e7|\e\[s/)   # cursor save
      expect(output).to match(/\e8|\e\[u/)   # cursor restore
      expect(output).to include("\e[2K")     # clear line (at least once)
      expect(reader.instance_variable_get(:@menu_lines_printed)).to eq(0)
    end

    it "draw_menu_items emits nothing when menu has no suggestions" do
      reader = make_reader
      palette = instance_double(OllamaAgent::RuntimeCommandSystem::CommandPalette)
      menu = OllamaAgent::RuntimeCommandSystem::InteractiveMenu.new
      allow(palette).to receive(:menu).and_return(menu)
      reader.instance_variable_set(:@command_palette, palette)
      reader.send(:draw_menu_items)
      expect(out.string).to be_empty
    end

    it "close_completion_menu hides menu and resets menu_lines_printed" do
      reader = make_reader
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
end

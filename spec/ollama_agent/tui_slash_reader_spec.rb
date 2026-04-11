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
end

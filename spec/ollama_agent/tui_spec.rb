# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/ollama_agent/tui"

RSpec.describe OllamaAgent::TUI do
  let(:out) { StringIO.new }

  describe "#ask_interactive" do
    it "returns the first option value in god mode without prompting" do
      tui = described_class.new(stdout: out, stderr: out, god_mode: true)
      choice = tui.ask_interactive(
        "Choose",
        [{ name: "Alpha", value: :a }, { name: "Beta", value: :b }]
      )
      expect(choice).to eq(:a)
    end

    it "respects explicit god_mode: false when instance god_mode is true" do
      tui = described_class.new(stdout: out, stderr: out, god_mode: true)
      prompt = instance_double(TTY::Prompt)
      allow(prompt).to receive(:select).and_return(:picked)
      tui.instance_variable_set(:@prompt, prompt)
      choice = tui.ask_interactive("Q", [{ name: "A", value: :a }], god_mode: false)
      expect(choice).to eq(:picked)
    end
  end

  describe "#render_assistant_message" do
    let(:msg_class) do
      Struct.new(:thinking, :content)
    end

    it "prints thinking and content to stdout" do
      tui = described_class.new(stdout: out, stderr: out)
      tui.render_assistant_message(msg_class.new("Reasoning", "Hello **world**"))
      buf = out.string
      expect(buf).to include("Thinking")
      expect(buf).to include("Reasoning")
      expect(buf).to include("Assistant")
    end
  end
end

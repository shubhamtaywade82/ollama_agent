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

  describe "history persistence" do
    require "tmpdir"
    let(:temp_dir) { Dir.mktmpdir }
    let(:temp_history_file) { File.join(temp_dir, "repl_history") }

    before do
      stub_const("OllamaAgent::TUI::HISTORY_FILE", temp_history_file)
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it "loads history from file on initialization" do
      File.write(temp_history_file, "command1\ncommand2\n")
      tui = described_class.new(stdout: out, stderr: out)
      reader = tui.instance_variable_get(:@slash_reader)
      history = reader.instance_variable_get(:@history)
      expect(history.to_a).to eq(%w[command1 command2])
    end

    it "saves history to file after reading a line" do
      tui = described_class.new(stdout: out, stderr: out)
      reader = tui.instance_variable_get(:@slash_reader)
      
      # Mock the actual terminal read to return user input and update history
      allow(reader).to receive(:read_line).and_wrap_original do |original_method, *args|
        reader.add_to_history("new_command")
        "new_command"
      end
      
      tui.ask_user_line(completion_candidates: ["/help"])

      expect(File.exist?(temp_history_file)).to be true
      expect(File.read(temp_history_file).strip).to eq("new_command")
    end
  end

  describe "#ask_user_line with prompt_prefix" do
    it "includes prompt_prefix in the string passed to read_line" do
      captured_prompt = nil
      slash_reader = instance_double(OllamaAgent::TuiSlashReader)
      allow(slash_reader).to receive(:completion_candidates=)
      allow(slash_reader).to receive(:command_palette=)
      allow(slash_reader).to receive(:read_line) { |prompt| captured_prompt = prompt; "" }

      tui = described_class.new(stdout: StringIO.new)
      tui.instance_variable_set(:@slash_reader, slash_reader)
      tui.ask_user_line(prompt_prefix: "[qwen3:32b] ")

      expect(captured_prompt).to include("[qwen3:32b]")
    end
  end
end

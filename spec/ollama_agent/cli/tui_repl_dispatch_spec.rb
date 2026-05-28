# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/cli/tui_repl"

RSpec.describe OllamaAgent::CLI::TuiRepl do
  let(:stdout) { StringIO.new }
  let(:agent) do
    instance_double(
      OllamaAgent::Agent,
      model: "qwen3:32b",
      provider_name: "local"
    )
  end
  let(:tui) { instance_double(OllamaAgent::TUI, log: nil) }

  before do
    allow(OllamaAgent::Plugins::Registry).to receive(:all_command_handlers).and_return([])
    allow(OllamaAgent::Providers::ModelRegistry).to receive(:find).and_return(nil)
    allow(agent).to receive(:assign_chat_model!).and_return("deepseek-r1")
  end

  subject(:repl) { described_class.new(agent: agent, tui: tui, stdout: stdout) }

  describe "#dispatch_slash routing" do
    it "routes /model <name> through the RuntimeDispatcher (calls assign_chat_model!)" do
      repl.send(:dispatch_slash, "/model deepseek-r1")
      expect(agent).to have_received(:assign_chat_model!).with("deepseek-r1")
    end

    it "falls back to handle_slash for /help" do
      expect(repl).to receive(:handle_slash).with("/help")
      repl.send(:dispatch_slash, "/help")
    end

    it "falls back to handle_slash for bare /model (no arg)" do
      expect(repl).to receive(:handle_slash).with("/model")
      repl.send(:dispatch_slash, "/model")
    end

    it "falls back to handle_slash for /model list" do
      expect(repl).to receive(:handle_slash).with("/model list")
      repl.send(:dispatch_slash, "/model list")
    end

    it "falls back to handle_slash for /model with trailing space (no name)" do
      expect(repl).to receive(:handle_slash).with("/model ")
      repl.send(:dispatch_slash, "/model ")
    end
  end

  describe "session_runtime" do
    it "reflects current model from agent" do
      expect(repl.send(:session_runtime).active_model).to eq("qwen3:32b")
    end
  end
end

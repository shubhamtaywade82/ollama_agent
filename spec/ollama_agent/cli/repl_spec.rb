# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "ollama_agent/cli/repl"

RSpec.describe OllamaAgent::CLI::Repl do
  let(:agent) { instance_double(OllamaAgent::Agent) }
  let(:stdout) { StringIO.new }
  subject(:repl) { described_class.new(agent: agent, stdout: stdout) }

  before do
    allow(agent).to receive(:model).and_return("gpt-4o")
    allow(agent).to receive(:list_local_model_names).and_return([])
    allow(agent).to receive(:list_cloud_model_names).and_return([])
  end

  describe "/models command" do
    it "renders the registered models grouped by provider and marks current model" do
      repl.send(:handle_slash, "/models")
      output = stdout.string
      expect(output).to include("Registered Inference Models:")
      expect(output).to include("OPENAI")
      expect(output).to include("gpt-4o")
    end

    it "filters the model list based on search query" do
      repl.send(:handle_slash, "/models claude")
      output = stdout.string
      expect(output).to include("claude")
      expect(output).not_to include("gpt-4o")
    end
  end

  describe "/model command" do
    it "shows current model when arg is empty" do
      repl.send(:handle_slash, "/model")
      expect(stdout.string).to include("Current chat model: gpt-4o")
    end

    it "updates the model on the agent" do
      expect(agent).to receive(:assign_chat_model!).with("gpt-4o-mini").and_return("gpt-4o-mini")
      repl.send(:handle_slash, "/model gpt-4o-mini")
      expect(stdout.string).to include("Chat model switched to")
      expect(stdout.string).to include("gpt-4o-mini")
    end
  end
end

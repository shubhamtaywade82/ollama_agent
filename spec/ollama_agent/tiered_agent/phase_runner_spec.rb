# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::TieredAgent::PhaseRunner do
  let(:vram_options) { OllamaAgent::TieredAgent::VramOptions.build }
  let(:client)       { instance_double("Ollama::Client") }
  let(:message)      { instance_double("Ollama::Message") }
  let(:response)     { instance_double("Ollama::Response", message: message) }
  let(:state_log)    { OllamaAgent::TieredAgent::StateLog.new }

  subject(:runner) { described_class.new(client: client, vram_options: vram_options) }

  def stub_chat_with_json(json_hash)
    allow(message).to receive(:content).and_return(JSON.generate(json_hash))
    allow(client).to receive(:chat).and_return(response)
  end

  describe "#run_planning" do
    it "targets the Medium model" do
      stub_chat_with_json("rationale" => "do X", "tool_call" => "execute_bash",
                          "tool_instructions" => "run ls")
      expect(client).to receive(:chat).with(
        hash_including(model: OllamaAgent::TieredAgent::ModelTier::MEDIUM)
      ).and_return(response)
      runner.run_planning(goal: "test goal", state_log: state_log)
    end

    it "passes the format schema" do
      stub_chat_with_json("rationale" => "r", "tool_call" => "exit_success",
                          "tool_instructions" => "done")
      expect(client).to receive(:chat).with(
        hash_including(format: described_class::PLANNING_SCHEMA)
      ).and_return(response)
      runner.run_planning(goal: "goal", state_log: state_log)
    end

    it "returns a parsed hash" do
      stub_chat_with_json("rationale" => "r", "tool_call" => "exit_success",
                          "tool_instructions" => "done")
      result = runner.run_planning(goal: "goal", state_log: state_log)
      expect(result).to include("tool_call" => "exit_success")
    end

    it "raises OllamaAgent::Error when the model returns invalid JSON" do
      allow(message).to receive(:content).and_return("not json }{")
      allow(client).to receive(:chat).and_return(response)
      expect { runner.run_planning(goal: "goal", state_log: state_log) }
        .to raise_error(OllamaAgent::Error, /invalid JSON/)
    end
  end

  describe "#run_extraction" do
    it "targets the Small model" do
      stub_chat_with_json("command" => "ls -la")
      expect(client).to receive(:chat).with(
        hash_including(model: OllamaAgent::TieredAgent::ModelTier::SMALL)
      ).and_return(response)
      runner.run_extraction(tool_name: "execute_bash", instructions: "list files")
    end

    it "uses a command-only schema for execute_bash" do
      stub_chat_with_json("command" => "ls")
      expect(client).to receive(:chat).with(
        hash_including(format: hash_including("required" => ["command"]))
      ).and_return(response)
      runner.run_extraction(tool_name: "execute_bash", instructions: "list")
    end

    it "uses a path+data schema for read/write tools" do
      stub_chat_with_json("path" => "/tmp/f", "data" => "content")
      expect(client).to receive(:chat).with(
        hash_including(format: hash_including("required" => %w[path data]))
      ).and_return(response)
      runner.run_extraction(tool_name: "write_output_file", instructions: "write something")
    end
  end

  describe "#run_verification" do
    it "targets the Medium model" do
      stub_chat_with_json("confirmed_success" => true, "reasons" => "output looks good")
      expect(client).to receive(:chat).with(
        hash_including(model: OllamaAgent::TieredAgent::ModelTier::MEDIUM)
      ).and_return(response)
      runner.run_verification(tool: "execute_bash", args: { "command" => "ls" }, output: "file1\n")
    end

    it "returns success/reasons hash" do
      stub_chat_with_json("confirmed_success" => false, "reasons" => "command failed")
      result = runner.run_verification(tool: "execute_bash", args: {}, output: "error")
      expect(result).to include("confirmed_success" => false, "reasons" => "command failed")
    end

    it "truncates very long output to 2048 chars" do
      stub_chat_with_json("confirmed_success" => true, "reasons" => "ok")
      long_output = "x" * 10_000
      allow(client).to receive(:chat) do |**kwargs|
        user_content = kwargs[:messages].last["content"]
        expect(user_content.length).to be <= 2200
        response
      end
      runner.run_verification(tool: "t", args: {}, output: long_output)
    end
  end

  describe "#run_escalation" do
    it "targets the Large model" do
      allow(message).to receive(:content).and_return("Try a different approach")
      expect(client).to receive(:chat).with(
        hash_including(model: OllamaAgent::TieredAgent::ModelTier::LARGE)
      ).and_return(response)
      runner.run_escalation(goal: "goal", state_log: state_log)
    end

    it "does NOT pass a format schema (free-form text)" do
      allow(message).to receive(:content).and_return("Escalation advice")
      expect(client).to receive(:chat).with(
        hash_not_including(:format)
      ).and_return(response)
      runner.run_escalation(goal: "goal", state_log: state_log)
    end

    it "returns the supervisor recommendation as a string" do
      allow(message).to receive(:content).and_return("Use tool X instead")
      allow(client).to receive(:chat).and_return(response)
      result = runner.run_escalation(goal: "goal", state_log: state_log)
      expect(result).to eq("Use tool X instead")
    end
  end

  describe "model overrides" do
    it "uses the override Small model when provided" do
      runner_with_override = described_class.new(
        client: client,
        vram_options: vram_options,
        models: { small: "custom-small:latest" }
      )
      stub_chat_with_json("command" => "ls")
      expect(client).to receive(:chat).with(
        hash_including(model: "custom-small:latest")
      ).and_return(response)
      runner_with_override.run_extraction(tool_name: "execute_bash", instructions: "list")
    end
  end
end

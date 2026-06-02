# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/runtime_command_system/session/events"
require "ollama_agent/runtime_command_system/session/runtime"

RSpec.describe OllamaAgent::RuntimeCommandSystem::Session::Runtime do
  let(:agent) do
    instance_double(OllamaAgent::Agent, model: "qwen3:32b", provider_name: "local")
  end

  subject(:runtime) { described_class.new(agent: agent) }

  it "delegates active_model to agent" do
    expect(runtime.active_model).to eq("qwen3:32b")
  end

  it "delegates active_provider to agent" do
    expect(runtime.active_provider).to eq("local")
  end

  it "exposes the agent" do
    expect(runtime.agent).to be(agent)
  end

  it "exposes an Events instance" do
    expect(runtime.events).to be_a(OllamaAgent::RuntimeCommandSystem::Session::Events)
  end

  describe "#switch_model!" do
    before do
      allow(agent).to receive(:assign_chat_model!).with("deepseek-r1").and_return("deepseek-r1")
    end

    it "calls agent.assign_chat_model!" do
      runtime.switch_model!("deepseek-r1")
      expect(agent).to have_received(:assign_chat_model!).with("deepseek-r1")
    end

    it "emits :model_switched event with model name" do
      received = nil
      runtime.events.on(:model_switched) { |p| received = p }
      runtime.switch_model!("deepseek-r1")
      expect(received[:model]).to eq("deepseek-r1")
    end

    it "passes descriptor in event payload when provided" do
      descriptor = double("descriptor")
      received = nil
      runtime.events.on(:model_switched) { |p| received = p }
      runtime.switch_model!("deepseek-r1", descriptor: descriptor)
      expect(received[:descriptor]).to be(descriptor)
    end

    it "returns the model name" do
      expect(runtime.switch_model!("deepseek-r1")).to eq("deepseek-r1")
    end
  end

  describe "#state" do
    it "returns a hash with model and provider" do
      expect(runtime.state).to eq(model: "qwen3:32b", provider: "local")
    end
  end

  describe "#export_state" do
    it "includes timestamp key" do
      expect(runtime.export_state).to include(:timestamp)
    end

    it "includes model and provider" do
      exported = runtime.export_state
      expect(exported[:model]).to eq("qwen3:32b")
      expect(exported[:provider]).to eq("local")
    end
  end
end

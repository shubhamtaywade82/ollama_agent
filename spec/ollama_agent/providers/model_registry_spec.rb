# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/providers/model_registry"

RSpec.describe OllamaAgent::Providers::ModelRegistry do
  let(:agent) { instance_double(OllamaAgent::Agent) }

  before do
    allow(agent).to receive(:list_local_model_names).and_return([])
    allow(agent).to receive(:list_cloud_model_names).and_return([])
    allow(described_class).to receive(:fetch_local_models).and_return([])
  end

  describe ".all" do
    it "returns known model descriptors" do
      list = described_class.all
      expect(list).not_to be_empty
      expect(list.any? { |m| m.name == "gpt-4o" }).to be true
    end

    it "includes local Ollama models when agent is supplied" do
      allow(agent).to receive(:list_local_model_names).and_return(["qwen2.5-coder:14b", "deepseek-r1:8b"])
      list = described_class.all(agent: agent)
      
      qwen = list.find { |m| m.name == "qwen2.5-coder:14b" }
      expect(qwen).not_to be_nil
      expect(qwen.provider).to eq("local")
      expect(qwen.tools?).to be true

      deepseek = list.find { |m| m.name == "deepseek-r1:8b" }
      expect(deepseek).not_to be_nil
      expect(deepseek.reasoning?).to be true
    end
  end

  describe ".find" do
    it "finds a registered model by name case-insensitively" do
      model = described_class.find("GPT-4O")
      expect(model).not_to be_nil
      expect(model.name).to eq("gpt-4o")
      expect(model.provider).to eq("openai")
    end

    it "returns nil when model not registered" do
      expect(described_class.find("unknown")).to be_nil
    end
  end
end

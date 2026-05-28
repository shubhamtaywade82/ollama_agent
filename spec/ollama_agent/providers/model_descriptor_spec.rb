# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/providers/model_descriptor"

RSpec.describe OllamaAgent::Providers::ModelDescriptor do
  subject(:descriptor) do
    described_class.new(
      name: "qwen2.5-coder:14b",
      provider: "local",
      context_size: 32_768,
      capabilities: [:chat, :tools],
      size_gb: 9.2,
      status: "loaded"
    )
  end

  describe "initialization" do
    it "sets basic attributes" do
      expect(descriptor.name).to eq("qwen2.5-coder:14b")
      expect(descriptor.provider).to eq("local")
      expect(descriptor.context_size).to eq(32_768)
      expect(descriptor.size_gb).to eq(9.2)
      expect(descriptor.status).to eq("loaded")
    end
  end

  describe "capability helpers" do
    it "identifies tool calling capability" do
      expect(descriptor.tools?).to be true
      expect(descriptor.vision?).to be false
      expect(descriptor.reasoning?).to be false
    end
  end
end

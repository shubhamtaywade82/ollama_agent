# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::KernelFeature do
  describe ".enabled?" do
    around do |example|
      original_value = ENV.fetch("OLLAMA_AGENT_KERNEL", nil)
      example.run
      ENV["OLLAMA_AGENT_KERNEL"] = original_value
    end

    it "returns true only when env is true" do
      ENV["OLLAMA_AGENT_KERNEL"] = "true"
      expect(described_class.enabled?).to be(true)

      ENV["OLLAMA_AGENT_KERNEL"] = "1"
      expect(described_class.enabled?).to be(false)

      ENV["OLLAMA_AGENT_KERNEL"] = nil
      expect(described_class.enabled?).to be(false)
    end
  end
end

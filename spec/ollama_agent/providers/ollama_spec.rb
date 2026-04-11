# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/providers/ollama"

RSpec.describe OllamaAgent::Providers::Ollama do
  describe "#build_client" do
    it "returns RetryMiddleware wrapping an Ollama::Client" do
      fake_inner = instance_double(Ollama::Client)
      allow(Ollama::Client).to receive(:new).and_return(fake_inner)

      provider = described_class.new
      wrapped = provider.send(:build_client)

      expect(wrapped).to be_a(OllamaAgent::Resilience::RetryMiddleware)
      expect(wrapped.instance_variable_get(:@client)).to eq(fake_inner)
    end
  end
end

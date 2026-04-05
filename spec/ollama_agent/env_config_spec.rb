# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::EnvConfig do
  describe ".fetch_int" do
    it "returns default when variable is unset" do
      ENV.delete("OLLAMA_AGENT_ENV_CONFIG_SPEC_INT")
      expect(described_class.fetch_int("OLLAMA_AGENT_ENV_CONFIG_SPEC_INT", 42)).to eq(42)
    end

    it "parses a valid integer" do
      ENV["OLLAMA_AGENT_ENV_CONFIG_SPEC_INT"] = "7"
      expect(described_class.fetch_int("OLLAMA_AGENT_ENV_CONFIG_SPEC_INT", 0)).to eq(7)
    ensure
      ENV.delete("OLLAMA_AGENT_ENV_CONFIG_SPEC_INT")
    end

    it "returns default for non-numeric value" do
      ENV["OLLAMA_AGENT_ENV_CONFIG_SPEC_INT"] = "abc"
      expect(described_class.fetch_int("OLLAMA_AGENT_ENV_CONFIG_SPEC_INT", 99)).to eq(99)
    ensure
      ENV.delete("OLLAMA_AGENT_ENV_CONFIG_SPEC_INT")
    end

    it "raises ConfigurationError when strict: true and value is invalid" do
      ENV["OLLAMA_AGENT_ENV_CONFIG_SPEC_INT"] = "nope"
      expect do
        described_class.fetch_int("OLLAMA_AGENT_ENV_CONFIG_SPEC_INT", 1, strict: true)
      end.to raise_error(OllamaAgent::ConfigurationError, /not a valid integer/)
    ensure
      ENV.delete("OLLAMA_AGENT_ENV_CONFIG_SPEC_INT")
    end
  end

  describe ".fetch_float" do
    it "returns default for non-float value" do
      ENV["OLLAMA_AGENT_ENV_CONFIG_SPEC_FLOAT"] = "nope"
      expect(described_class.fetch_float("OLLAMA_AGENT_ENV_CONFIG_SPEC_FLOAT", 1.5)).to eq(1.5)
    ensure
      ENV.delete("OLLAMA_AGENT_ENV_CONFIG_SPEC_FLOAT")
    end

    it "raises ConfigurationError when strict: true and value is invalid" do
      ENV["OLLAMA_AGENT_ENV_CONFIG_SPEC_FLOAT"] = "bad"
      expect do
        described_class.fetch_float("OLLAMA_AGENT_ENV_CONFIG_SPEC_FLOAT", 1.0, strict: true)
      end.to raise_error(OllamaAgent::ConfigurationError, /not a valid float/)
    ensure
      ENV.delete("OLLAMA_AGENT_ENV_CONFIG_SPEC_FLOAT")
    end
  end

  describe ".strict_env?" do
    it "is true when OLLAMA_AGENT_STRICT_ENV is 1" do
      ENV["OLLAMA_AGENT_STRICT_ENV"] = "1"
      expect(described_class.strict_env?).to be true
    ensure
      ENV.delete("OLLAMA_AGENT_STRICT_ENV")
    end
  end
end

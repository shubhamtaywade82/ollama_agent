# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::ThinkParam do
  describe ".parse" do
    it "returns nil for blank" do
      expect(described_class.parse(nil)).to be_nil
      expect(described_class.parse("")).to be_nil
    end

    it "returns booleans for common strings" do
      expect(described_class.parse("true")).to be true
      expect(described_class.parse("false")).to be false
    end

    it "returns level strings" do
      expect(described_class.parse("high")).to eq("high")
    end
  end

  describe ".resolve" do
    it "uses ENV when CLI value is nil" do
      ENV["OLLAMA_AGENT_THINK"] = "true"
      expect(described_class.resolve(nil)).to be true
    ensure
      ENV.delete("OLLAMA_AGENT_THINK")
    end

    it "prefers CLI value over ENV" do
      ENV["OLLAMA_AGENT_THINK"] = "true"
      expect(described_class.resolve("false")).to be false
    ensure
      ENV.delete("OLLAMA_AGENT_THINK")
    end
  end

  describe ".effective_for_model" do
    it "passes through non-true values" do
      expect(described_class.effective_for_model(nil, "gpt-oss:120b-cloud")).to be_nil
      expect(described_class.effective_for_model(false, "gpt-oss:120b-cloud")).to be false
      expect(described_class.effective_for_model("high", "gpt-oss:120b-cloud")).to eq("high")
    end

    it "maps true to medium for gpt-oss models" do
      ENV.delete("OLLAMA_AGENT_GPT_OSS_THINK")
      expect(described_class.effective_for_model(true, "gpt-oss:120b-cloud")).to eq("medium")
    end

    it "maps true using OLLAMA_AGENT_GPT_OSS_THINK when set" do
      ENV["OLLAMA_AGENT_GPT_OSS_THINK"] = "high"
      expect(described_class.effective_for_model(true, "gpt-oss:120b-cloud")).to eq("high")
    ensure
      ENV.delete("OLLAMA_AGENT_GPT_OSS_THINK")
    end

    it "leaves true unchanged for non-gpt-oss models" do
      expect(described_class.effective_for_model(true, "llama3.2")).to be true
    end
  end
end

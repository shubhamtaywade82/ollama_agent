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
end

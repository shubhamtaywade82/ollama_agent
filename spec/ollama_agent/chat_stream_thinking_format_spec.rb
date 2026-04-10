# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/ollama_agent/chat_stream_thinking_format"

RSpec.describe OllamaAgent::ChatStreamThinkingFormat do
  describe ".coerce_thinking_to_string" do
    it "returns strings unchanged" do
      expect(described_class.coerce_thinking_to_string("plan")).to eq("plan")
    end

    it "joins arrays of strings" do
      expect(described_class.coerce_thinking_to_string(%w[a b])).to eq("ab")
    end

    it "serializes hashes as JSON" do
      expect(described_class.coerce_thinking_to_string({ "k" => 1 })).to eq('{"k":1}')
    end
  end

  describe ".normalize_message_thinking!" do
    it "replaces non-string thinking with a string so downstream String#<< is safe" do
      msg = { "thinking" => { "step" => 1 } }
      described_class.normalize_message_thinking!(msg)
      expect(msg["thinking"]).to eq('{"step":1}')
    end

    it "leaves string thinking unchanged" do
      msg = { "thinking" => "ok" }
      described_class.normalize_message_thinking!(msg)
      expect(msg["thinking"]).to eq("ok")
    end
  end
end

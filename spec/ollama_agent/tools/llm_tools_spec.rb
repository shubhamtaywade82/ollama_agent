# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::LlmComplete do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("llm_complete")
    end

    it "is read_only safe" do
      expect(tool.read_only_safe).to be(true)
    end
  end

  describe "#call" do
    it "returns a result (Ollama may or may not be available)" do
      result = tool.call({ "prompt" => "hello" }, context: {})
      expect([Hash, String]).to include(result.class)
    end
  end
end

RSpec.describe OllamaAgent::Tools::LlmReview do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("llm_review")
    end
  end

  describe "#call" do
    it "returns a result when called (Ollama may or may not be available)" do
      result = tool.call({ "code" => "puts 1", "instructions" => "check style" }, context: {})
      expect([Hash, String]).to include(result.class)
    end
  end
end

RSpec.describe OllamaAgent::Tools::EmbedText do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("embed_text")
    end
  end

  describe "#call" do
    it "returns a hash with vector or error" do
      result = tool.call({ "text" => "hello world" }, context: {})
      expect(result).to be_a(Hash)
      expect(result).to have_key(:dimensions).or have_key(:error)
    end
  end
end

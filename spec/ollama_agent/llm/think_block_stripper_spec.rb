# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::LLM::ThinkBlockStripper do
  describe ".strip" do
    it "removes think tags and keeps execution payload" do
      payload = '<think>hidden reasoning</think>{"tool":"read_file"}'

      expect(described_class.strip(payload)).to eq('{"tool":"read_file"}')
    end
  end
end

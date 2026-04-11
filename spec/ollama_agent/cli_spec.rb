# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/ollama_agent/cli"

RSpec.describe OllamaAgent::CLI do
  it "uses ask as the default Thor task so bare ollama_agent opens the interactive flow" do
    expect(described_class.default_task).to eq("ask")
  end
end

# frozen_string_literal: true

# rubocop:disable RSpec/SpecFilePathFormat -- groups SlashCompletion with reader smoke tests
require "spec_helper"
require_relative "../../lib/ollama_agent/tui_slash_reader"

RSpec.describe OllamaAgent::SlashCompletion do
  describe ".longest_common_prefix" do
    it "returns the shared prefix" do
      expect(described_class.longest_common_prefix(%w[/model /models])).to eq("/model")
    end

    it "returns empty for an empty list" do
      expect(described_class.longest_common_prefix([])).to eq("")
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat

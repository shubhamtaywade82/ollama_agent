# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/runtime_command_system/suggestion"

RSpec.describe OllamaAgent::RuntimeCommandSystem::Suggestion do
  describe "#display_text" do
    it "shows text only when no description and no capabilities" do
      s = described_class.new(text: "/help", type: :command)
      expect(s.display_text).to eq("/help")
    end

    it "shows text and description with padding when no capabilities" do
      s = described_class.new(text: "/model", type: :command, description: "Switch model")
      expect(s.display_text).to include("/model")
      expect(s.display_text).to include("Switch model")
    end

    it "shows capability badges in brackets after description" do
      s = described_class.new(
        text: "qwen3:32b",
        type: :model,
        description: "local • 32k • loaded",
        capabilities: %i[tools]
      )
      text = s.display_text
      expect(text).to include("qwen3:32b")
      expect(text).to include("local • 32k • loaded")
      expect(text).to include("[tools]")
    end

    it "shows multiple capability badges space-separated" do
      s = described_class.new(
        text: "gemma3",
        type: :model,
        description: "local",
        capabilities: %i[vision reasoning]
      )
      expect(s.display_text).to include("[vision]")
      expect(s.display_text).to include("[reasoning]")
    end

    it "aligns to 30-char name column" do
      s = described_class.new(
        text: "qwen3:32b",
        type: :model,
        description: "local • 32k",
        capabilities: %i[tools]
      )
      # name column is left-padded to 30 chars
      expect(s.display_text).to start_with("qwen3:32b".ljust(30))
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/runtime_command_system/command_palette"

RSpec.describe OllamaAgent::RuntimeCommandSystem::CommandPalette do
  subject(:palette) { described_class.new(commands: commands, session: { agent: agent }) }

  let(:commands) do
    {
      "/model" => "Switch active model",
      "/models" => "List models",
      "/provider" => "Switch provider",
      "/help" => "Show help"
    }
  end

  let(:agent) { instance_double(OllamaAgent::Agent) }

  before do
    allow(OllamaAgent::Providers::ModelRegistry).to receive(:all).and_return([
                                                                               OllamaAgent::Providers::ModelDescriptor.new(
                                                                                 name: "qwen3:32b",
                                                                                 provider: "local",
                                                                                 context_size: 32_768,
                                                                                 capabilities: %i[chat tools],
                                                                                 status: "loaded"
                                                                               ),
                                                                               OllamaAgent::Providers::ModelDescriptor.new(
                                                                                 name: "deepseek-r1:8b",
                                                                                 provider: "local",
                                                                                 context_size: 32_768,
                                                                                 capabilities: %i[chat reasoning],
                                                                                 status: "available"
                                                                               )
                                                                             ])
  end

  it "suggests slash commands by prefix" do
    suggestions = palette.suggestions("/mod")

    expect(suggestions.map(&:text)).to include("/model", "/models")
    expect(palette.ghost_text("/mod").suffix).to eq("el")
  end

  it "delegates /model arguments to the model registry" do
    suggestions = palette.suggestions("/model qw")

    expect(suggestions.map(&:text)).to eq(["qwen3:32b"])
    expect(suggestions.first.description).to include("local")
    expect(suggestions.first.capabilities).to include(:tools)
  end

  it "computes model ghost text without mutating the typed prefix" do
    ghost = palette.ghost_text("/model qwen")

    expect(ghost.suffix).to eq("3:32b")
    expect(ghost.full_completion).to eq("/model qwen3:32b")
  end

  it "suggests providers for /provider arguments" do
    suggestions = palette.suggestions("/provider gro")

    expect(suggestions.map(&:text)).to include("groq")
    expect(suggestions.first.type).to eq(:provider)
  end
end

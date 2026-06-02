# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/runtime_command_system/input_buffer"
require "ollama_agent/runtime_command_system/ghost_text"

RSpec.describe OllamaAgent::RuntimeCommandSystem::Input::Buffer do
  it "keeps command editing isolated from chat runtime mutation" do
    buffer = described_class.new("/mod")
    ghost = OllamaAgent::RuntimeCommandSystem::GhostText.new(
      suffix: "el",
      full_completion: "/model",
      suggestion: nil
    )

    buffer.accept_ghost_text(ghost)
    buffer.insert(" q")
    buffer.backspace

    expect(buffer.text).to eq("/model ")
    expect(buffer.command_mode?).to be true
  end
end

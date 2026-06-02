# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/runtime_command_system/session/events"

RSpec.describe OllamaAgent::RuntimeCommandSystem::Session::Events do
  subject(:events) { described_class.new }

  it "calls registered handler when event emitted" do
    received = nil
    events.on(:model_switched) { |p| received = p }
    events.emit(:model_switched, model: "qwen3:32b")
    expect(received).to eq(model: "qwen3:32b")
  end

  it "swallows errors raised inside handlers" do
    events.on(:model_switched) { raise "boom" }
    expect { events.emit(:model_switched, {}) }.not_to raise_error
  end

  it "subscribed? returns false with no handlers" do
    expect(events.subscribed?(:model_switched)).to be false
  end

  it "subscribed? returns true after registering a handler" do
    events.on(:model_switched) { nil }
    expect(events.subscribed?(:model_switched)).to be true
  end

  it "requires a block when registering" do
    expect { events.on(:model_switched) }.to raise_error(ArgumentError)
  end
end

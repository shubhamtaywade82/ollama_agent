# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ollama_agent/streaming/hooks"

RSpec.describe OllamaAgent::Streaming::Hooks do
  subject(:hooks) { described_class.new }

  describe "#on and #emit" do
    it "calls a registered handler when the event is emitted" do
      received = []
      hooks.on(:on_token) { |p| received << p[:token] }
      hooks.emit(:on_token, { token: "hello", turn: 1 })
      expect(received).to eq(["hello"])
    end

    it "calls multiple handlers for the same event" do
      calls = []
      hooks.on(:on_complete) { |_| calls << :a }
      hooks.on(:on_complete) { |_| calls << :b }
      hooks.emit(:on_complete, { messages: [], turns: 1 })
      expect(calls).to contain_exactly(:a, :b)
    end

    it "does nothing when no handler is registered for an event" do
      expect { hooks.emit(:on_token, { token: "x", turn: 1 }) }.not_to raise_error
    end

    it "silently ignores unknown event names on emit" do
      expect { hooks.emit(:unknown_event, {}) }.not_to raise_error
    end

    it "swallows handler exceptions so a bad subscriber never crashes the agent" do
      hooks.on(:on_token) { |_| raise "boom" }
      expect { hooks.emit(:on_token, { token: "x", turn: 1 }) }.not_to raise_error
    end

    it "continues calling subsequent handlers after one raises" do
      calls = []
      hooks.on(:on_token) { |_| raise "boom" }
      hooks.on(:on_token) { |_| calls << :second }
      hooks.emit(:on_token, { token: "x", turn: 1 })
      expect(calls).to eq([:second])
    end
  end

  describe "#subscribed?" do
    it "returns false when no handler registered" do
      expect(hooks.subscribed?(:on_token)).to be false
    end

    it "returns true after a handler is registered" do
      hooks.on(:on_token) { |_payload| nil }
      expect(hooks.subscribed?(:on_token)).to be true
    end
  end

  describe "EVENTS constant" do
    it "includes all expected event names" do
      expected = %i[on_token on_chunk on_tool_call on_tool_result on_complete on_error on_retry]
      expected.each { |e| expect(described_class::EVENTS).to include(e) }
    end
  end
end

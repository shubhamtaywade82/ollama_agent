# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ollama_agent/streaming/hooks"
require_relative "../../../lib/ollama_agent/streaming/console_streamer"

RSpec.describe OllamaAgent::Streaming::ConsoleStreamer do
  subject(:streamer) { described_class.new }

  let(:hooks) { OllamaAgent::Streaming::Hooks.new }

  it "registers handlers for on_token, on_tool_call, on_tool_result, and on_complete" do
    streamer.attach(hooks)
    %i[on_token on_tool_call on_tool_result on_complete].each do |event|
      expect(hooks.subscribed?(event)).to be true
    end
  end

  it "prints a token when on_token fires" do
    streamer.attach(hooks)
    expect { hooks.emit(:on_token, { token: "hi", turn: 1 }) }.to output("hi").to_stdout
  end
end

# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ollama_agent/streaming/hooks"
require_relative "../../../lib/ollama_agent/streaming/console_streamer"

RSpec.describe OllamaAgent::Streaming::ConsoleStreamer do
  subject(:streamer) { described_class.new }

  let(:hooks) { OllamaAgent::Streaming::Hooks.new }

  it "registers handlers for on_thinking, on_token, on_tool_call, on_tool_result, and on_complete" do
    streamer.attach(hooks)
    %i[on_thinking on_token on_tool_call on_tool_result on_complete].each do |event|
      expect(hooks.subscribed?(event)).to be true
    end
  end

  it "prints a token when on_token fires" do
    streamer.attach(hooks)
    expect { hooks.emit(:on_token, { token: "hi", turn: 1 }) }.to output("hi").to_stdout
  end

  it "prints dim Thinking then Assistant heading before streamed content when thinking precedes tokens" do
    ENV["OLLAMA_AGENT_COLOR"] = "0"
    ENV.delete("NO_COLOR")
    OllamaAgent::Console.reset_thinking_session!
    streamer.attach(hooks)
    expect do
      hooks.emit(:on_thinking, { token: "plan", turn: 1 })
      hooks.emit(:on_token, { token: "hi", turn: 1 })
      hooks.emit(:on_complete, {})
    end.to output(<<~OUT).to_stdout
      Thinking
      plan
      Assistant
      hi
    OUT
  ensure
    ENV.delete("OLLAMA_AGENT_COLOR")
  end

  it "prints only the suffix when thinking payloads repeat cumulative text" do
    ENV["OLLAMA_AGENT_COLOR"] = "0"
    ENV.delete("NO_COLOR")
    OllamaAgent::Console.reset_thinking_session!
    streamer.attach(hooks)
    expect do
      hooks.emit(:on_thinking, { token: "ab", turn: 1 })
      hooks.emit(:on_thinking, { token: "abcd", turn: 1 })
      hooks.emit(:on_token, { token: "!", turn: 1 })
      hooks.emit(:on_complete, {})
    end.to output(<<~OUT).to_stdout
      Thinking
      abcd
      Assistant
      !
    OUT
  ensure
    ENV.delete("OLLAMA_AGENT_COLOR")
  end
end

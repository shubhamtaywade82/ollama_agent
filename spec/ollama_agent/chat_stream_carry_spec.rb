# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/ollama_agent/chat_stream_carry"

RSpec.describe OllamaAgent::ChatStreamCarry do
  describe ".next_last_data and .stitch_done_message_tool_calls!" do
    it "accumulates tool_calls across non-done chunks and stitches them onto a bare done row" do
      chunk1 = { "message" => { "role" => "assistant", "thinking" => "plan" } }
      chunk2 = { "message" => { "tool_calls" => [{ "id" => "1", "function" => { "name" => "list_files" } }] } }
      done = { "done" => true, "message" => { "role" => "assistant", "content" => "" } }

      carry1 = described_class.next_last_data(nil, chunk1)
      expect(carry1.dig("message", "tool_calls")).to be_nil

      carry2 = described_class.next_last_data(carry1, chunk2)
      expect(carry2.dig("message", "tool_calls").size).to eq(1)

      described_class.stitch_done_message_tool_calls!(done, carry2)
      expect(done.dig("message", "tool_calls").size).to eq(1)
      expect(done.dig("message", "tool_calls", 0, "function", "name")).to eq("list_files")
    end

    it "creates message on done row when missing but carry has tool_calls" do
      carry = { "message" => { "tool_calls" => [{ "id" => "x" }] } }
      done = { "done" => true }
      described_class.stitch_done_message_tool_calls!(done, carry)
      expect(done["message"]["tool_calls"].size).to eq(1)
    end
  end
end

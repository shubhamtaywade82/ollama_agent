# frozen_string_literal: true

require_relative "../../lib/ollama_agent/gemma_thought_content_parser"

RSpec.describe OllamaAgent::GemmaThoughtContentParser do
  describe ".process_chunk" do
    it "passes through when there is no content" do
      state = described_class.initial_state
      content, new_state, deltas = described_class.process_chunk(state, nil)
      expect(content).to be_nil
      expect(new_state).to eq(state)
      expect(deltas).to eq([])
    end

    it "passes through plain text with no markers" do
      state = described_class.initial_state
      content, new_state, deltas = described_class.process_chunk(state, "hello")
      expect(content).to eq("hello")
      expect(deltas).to eq([])
      expect(new_state["phase"]).to eq("content")
    end

    it "splits channel-thought markers in one chunk" do
      state = described_class.initial_state
      raw = "<|channel>thought\nline1\n<channel|>\nAnswer"
      content, _new_state, deltas = described_class.process_chunk(state, raw)
      expect(content).to eq("Answer")
      expect(deltas.join).to eq("line1\n")
    end

    it "streams thinking across chunks before the close marker" do
      state = described_class.initial_state
      c1, s1, d1 = described_class.process_chunk(state, "<|channel>thought\naa")
      expect(c1).to eq("")
      expect(d1.join).to eq("aa")

      c2, s2, d2 = described_class.process_chunk(s1, "bb")
      expect(c2).to eq("")
      expect(d2.join).to eq("bb")

      c3, _s3, d3 = described_class.process_chunk(s2, "<channel|>\nout")
      expect(c3).to eq("out")
      expect(d3).to eq([])
    end

    it "holds a partial open marker across chunks without leaking it to content" do
      state = described_class.initial_state
      c1, s1, d1 = described_class.process_chunk(state, "<|channel>thou")
      expect(c1).to eq("")
      expect(d1).to eq([])

      c2, _s2, d2 = described_class.process_chunk(s1, "ght\nx\n<channel|>\nok")
      expect(c2).to eq("ok")
      expect(d2.join).to eq("x\n")
    end

    it "handles redacted_thinking tags" do
      state = described_class.initial_state
      raw = "<redacted_thinking>secret</redacted_thinking>Hi"
      content, _s, deltas = described_class.process_chunk(state, raw)
      expect(content).to eq("Hi")
      expect(deltas.join).to eq("secret")
    end

    it "supports multiple thought blocks in one stream" do
      state = described_class.initial_state
      raw = "<|channel>thought\na<channel|>1<|channel>thought\nb<channel|>2"
      content, _s, _deltas = described_class.process_chunk(state, raw)
      expect(content).to eq("12")
    end
  end

  describe ".extract_from_complete_content" do
    it "returns nil thinking when there are no markers" do
      thinking, visible = described_class.extract_from_complete_content("plain")
      expect(thinking).to be_nil
      expect(visible).to eq("plain")
    end

    it "returns split thinking and visible content" do
      raw = "<|channel>thought\nplan<channel|>reply"
      thinking, visible = described_class.extract_from_complete_content(raw)
      expect(thinking).to eq("plan")
      expect(visible).to eq("reply")
    end
  end

  describe ".merge_into_message_data!" do
    it "fills thinking and trims content on Ollama-style message hashes" do
      data = {
        "role" => "assistant",
        "content" => "<|channel>thought\nx<channel|>y"
      }
      msg = Ollama::Response::Message.new(data)
      described_class.merge_into_message_data!(msg)
      expect(data["thinking"]).to eq("x")
      expect(data["content"]).to eq("y")
    end

    it "does not override non-empty API thinking" do
      data = { "role" => "assistant", "thinking" => "api", "content" => "body" }
      msg = Ollama::Response::Message.new(data)
      described_class.merge_into_message_data!(msg)
      expect(data["thinking"]).to eq("api")
      expect(data["content"]).to eq("body")
    end

    it "coerces non-string API thinking so it is treated as present" do
      data = { "role" => "assistant", "thinking" => %w[a b], "content" => "body" }
      msg = Ollama::Response::Message.new(data)
      described_class.merge_into_message_data!(msg)
      expect(data["thinking"]).to eq("ab")
      expect(data["content"]).to eq("body")
    end
  end
end

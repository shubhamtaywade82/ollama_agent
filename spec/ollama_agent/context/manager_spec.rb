# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ollama_agent/context/token_counter"
require_relative "../../../lib/ollama_agent/context/manager"

RSpec.describe OllamaAgent::Context::Manager do
  def sys_msg(content = "system prompt")
    { role: "system", content: content }
  end

  def user_msg(content)
    { role: "user", content: content }
  end

  def assistant_msg(content)
    { role: "assistant", content: content }
  end

  def tool_msg(name, content)
    { role: "tool", name: name, content: content }
  end

  describe "#trim (sliding window)" do
    it "returns messages unchanged when under budget" do
      manager  = described_class.new(max_tokens: 10_000)
      messages = [sys_msg, user_msg("hi"), assistant_msg("hello")]
      expect(manager.trim(messages)).to eq(messages)
    end

    it "never trims the system message" do
      system_content = "system " * 1000 # ~2000 chars ≈ 500 tokens
      manager  = described_class.new(max_tokens: 600)
      messages = [sys_msg(system_content), user_msg("short"), assistant_msg("short")]
      trimmed  = manager.trim(messages)
      expect(trimmed.first[:role]).to eq("system")
      expect(trimmed.first[:content]).to eq(system_content)
    end

    it "never trims the most recent user message" do
      big_history = Array.new(30) { |i| i.even? ? user_msg("x " * 200) : assistant_msg("y " * 200) }
      last_user   = user_msg("final question")
      messages    = [sys_msg] + big_history + [last_user]
      manager     = described_class.new(max_tokens: 500)
      trimmed     = manager.trim(messages)
      expect(trimmed.last).to eq(last_user)
    end

    it "does not mutate the original messages array" do
      messages = [sys_msg, user_msg("x " * 500), assistant_msg("y"), user_msg("last")]
      original = messages.dup
      manager  = described_class.new(max_tokens: 100)
      manager.trim(messages)
      expect(messages).to eq(original)
    end

    it "trims oldest messages first when over budget" do
      old_user  = user_msg("old message " * 100)
      old_asst  = assistant_msg("old reply " * 100)
      last_user = user_msg("recent")
      messages  = [sys_msg, old_user, old_asst, last_user]
      manager   = described_class.new(max_tokens: 50)
      trimmed   = manager.trim(messages)
      expect(trimmed).not_to include(old_user)
      expect(trimmed).not_to include(old_asst)
      expect(trimmed).to     include(last_user)
    end
  end

  describe "env var OLLAMA_AGENT_MAX_TOKENS" do
    it "uses the env var as the default token budget" do
      messages = [sys_msg, user_msg("x " * 500), user_msg("last")]
      described_class.new # no explicit max_tokens
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("OLLAMA_AGENT_MAX_TOKENS", nil).and_return("100")
      small_manager = described_class.new
      trimmed = small_manager.trim(messages)
      expect(trimmed.size).to be < messages.size
    end
  end

  describe OllamaAgent::Context::TokenCounter do
    it "estimates tokens as chars / 4" do
      expect(described_class.estimate("hello")).to eq(1) # 5 / 4 = 1 (integer division)
      expect(described_class.estimate("x" * 400)).to eq(100)
    end
  end
end

# frozen_string_literal: true

require "fileutils"
require "spec_helper"

RSpec.describe OllamaAgent::ExternalAgents::Runner do
  let(:agent_def) { { "id" => "claude_cli", "model" => "claude-test-model" } }
  let(:root) { Dir.mktmpdir("ext-agent-runner") }

  around do |example|
    prior = ENV.fetch("ANTHROPIC_API_KEY", nil)
    example.run
    if prior.nil?
      ENV.delete("ANTHROPIC_API_KEY")
    else
      ENV["ANTHROPIC_API_KEY"] = prior
    end
  end

  after do
    FileUtils.rm_rf(root) if root && File.directory?(root)
  end

  it "calls AnthropicClient and does not shell out via Open3.capture3" do
    ENV["ANTHROPIC_API_KEY"] = "test-key"
    chat_payload = { content: "assistant reply", stop_reason: "end_turn", usage: {} }
    client = instance_double(OllamaAgent::LLM::AnthropicClient, chat: chat_payload)
    allow(OllamaAgent::LLM::AnthropicClient).to receive(:new).and_return(client)
    allow(Open3).to receive(:capture3).and_raise("Open3.capture3 should not be used")

    out = described_class.run(
      agent_def: agent_def,
      root: root,
      executable: "ignored",
      task: "do the thing",
      context_summary: "",
      paths: [],
      timeout_sec: 30
    )

    expect(out).to include("exit:0")
    expect(out).to include("assistant reply")
    expect(OllamaAgent::LLM::AnthropicClient).to have_received(:new).with(
      hash_including(api_key: "test-key", model: "claude-test-model", timeout_seconds: 30)
    )
    expect(client).to have_received(:chat).with(hash_including(messages: kind_of(Array)))
  end

  it "raises AnthropicAPIError when the API key is missing" do
    ENV.delete("ANTHROPIC_API_KEY")
    expect do
      described_class.run(
        agent_def: agent_def,
        root: root,
        executable: "ignored",
        task: "x",
        context_summary: "",
        paths: [],
        timeout_sec: 5
      )
    end.to raise_error(OllamaAgent::AnthropicAPIError, /ANTHROPIC_API_KEY/)
  end
end

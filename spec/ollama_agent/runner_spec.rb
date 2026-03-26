# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::Runner do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmpdir) }

  def stub_client_with(content)
    client = instance_double(Ollama::Client)
    allow(client).to receive(:chat).and_return(
      Ollama::Response.new("message" => { "role" => "assistant", "content" => content })
    )
    client
  end

  describe ".build" do
    it "returns a Runner instance" do
      expect(described_class.build(root: tmpdir)).to be_a(described_class)
    end

    it "exposes a Hooks instance via #hooks" do
      runner = described_class.build(root: tmpdir)
      expect(runner.hooks).to be_a(OllamaAgent::Streaming::Hooks)
    end

    it "accepts stream: true without error" do
      expect { described_class.build(root: tmpdir, stream: true) }.not_to raise_error
    end

    it "attaches a ConsoleStreamer subscriber when stream: true" do
      runner = described_class.build(root: tmpdir, stream: true)
      expect(runner.hooks.subscribed?(:on_token)).to be true
    end
  end

  describe "#run" do
    it "executes a query against the agent" do
      runner = described_class.build(root: tmpdir)
      # inject a stub client to avoid hitting real Ollama
      agent  = OllamaAgent::Agent.new(
        client:          stub_client_with("All done."),
        root:            tmpdir,
        confirm_patches: false
      )
      allow(runner).to receive(:agent).and_return(agent)
      expect { runner.run("hello") }.not_to raise_error
    end
  end

  describe "custom tool registration via OllamaAgent::Tools" do
    before { OllamaAgent::Tools.reset! }
    after  { OllamaAgent::Tools.reset! }

    it "registers a custom tool accessible via OllamaAgent::Tools" do
      OllamaAgent::Tools.register(:my_tool, schema: { description: "test", properties: {}, required: [] }) do |_args, root:, read_only:|
        "custom result"
      end
      expect(OllamaAgent::Tools.custom_tool?("my_tool")).to be true
    end
  end
end

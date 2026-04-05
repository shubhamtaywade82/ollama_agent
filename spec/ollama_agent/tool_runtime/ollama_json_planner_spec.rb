# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::ToolRuntime::OllamaJsonPlanner do
  let(:registry) do
    tool = Class.new(OllamaAgent::ToolRuntime::Tool) do
      def name = "noop"

      def description = "no op"

      def schema = { "type" => "object" }

      def call(args)
        args
      end
    end.new
    OllamaAgent::ToolRuntime::Registry.new([tool])
  end

  let(:memory) { OllamaAgent::ToolRuntime::Memory.new }

  def stub_chat_returning(content)
    client = instance_double(Ollama::Client)
    allow(client).to receive(:chat).and_return(
      Ollama::Response.new("message" => { "role" => "assistant", "content" => content })
    )
    client
  end

  it "returns a parsed tool hash from assistant content" do
    client = stub_chat_returning('{"tool":"noop","args":{"k":"v"}}')
    planner = described_class.new(client: client, model: "m")
    step = planner.next_step(context: "ctx", memory: memory, registry: registry)
    expect(step).to eq({ "tool" => "noop", "args" => { "k" => "v" } })
  end

  it "extracts JSON when the model adds a prefix line" do
    client = stub_chat_returning("Sure.\n{\"tool\":\"noop\",\"args\":{}}\n")
    planner = described_class.new(client: client, model: "m")
    step = planner.next_step(context: { "q" => 1 }, memory: memory, registry: registry)
    expect(step["tool"]).to eq("noop")
  end

  it "raises JsonParseError when content is not valid JSON object" do
    client = stub_chat_returning("just text")
    planner = described_class.new(client: client, model: "m")
    expect { planner.next_step(context: "c", memory: memory, registry: registry) }
      .to raise_error(OllamaAgent::ToolRuntime::JsonParseError)
  end

  it "passes chat options to the client" do
    client = instance_double(Ollama::Client)
    allow(client).to receive(:chat).with(
      hash_including(options: { temperature: 0.0 })
    ).and_return(
      Ollama::Response.new("message" => { "role" => "assistant", "content" => '{"tool":"noop","args":{}}' })
    )
    planner = described_class.new(client: client, model: "m", chat_options: { temperature: 0.0 })
    planner.next_step(context: "c", memory: memory, registry: registry)
    expect(client).to have_received(:chat).once
  end

  it "defaults model from OLLAMA_AGENT_MODEL when model keyword omitted" do
    client = instance_double(Ollama::Client)
    allow(client).to receive(:chat).with(hash_including(model: "from-env")).and_return(
      Ollama::Response.new("message" => { "role" => "assistant", "content" => '{"tool":"noop","args":{}}' })
    )
    old = ENV.fetch("OLLAMA_AGENT_MODEL", nil)
    ENV["OLLAMA_AGENT_MODEL"] = "from-env"
    planner = described_class.new(client: client)
    planner.next_step(context: "c", memory: memory, registry: registry)
    expect(client).to have_received(:chat).once
  ensure
    if old.nil? || old.to_s.empty?
      ENV.delete("OLLAMA_AGENT_MODEL")
    else
      ENV["OLLAMA_AGENT_MODEL"] = old
    end
  end

  it "defaults model from Ollama::Config when model omitted and env unset" do
    client = instance_double(Ollama::Client)
    allow(client).to receive(:chat).with(hash_including(model: "from-config")).and_return(
      Ollama::Response.new("message" => { "role" => "assistant", "content" => '{"tool":"noop","args":{}}' })
    )
    old = ENV.fetch("OLLAMA_AGENT_MODEL", nil)
    ENV.delete("OLLAMA_AGENT_MODEL")
    config = instance_double(Ollama::Config, model: "from-config")
    allow(Ollama::Config).to receive(:new).and_return(config)
    planner = described_class.new(client: client)
    planner.next_step(context: "c", memory: memory, registry: registry)
    expect(client).to have_received(:chat).once
  ensure
    ENV["OLLAMA_AGENT_MODEL"] = old if old && !old.to_s.empty?
  end
end

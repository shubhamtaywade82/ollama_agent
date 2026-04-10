# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::ToolRuntime::Registry do
  let(:sample_tool) do
    Class.new(OllamaAgent::ToolRuntime::Tool) do
      def name = "ping"

      def description = "pong"

      def schema = { "type" => "object" }

      def call(args)
        { "echo" => args["x"] }
      end
    end.new
  end

  describe "#register" do
    it "rejects duplicate names" do
      reg = described_class.new
      reg.register(sample_tool)
      expect { reg.register(sample_tool) }.to raise_error(ArgumentError, /duplicate tool name/)
    end
  end

  describe "#resolve" do
    let(:registry) { described_class.new([sample_tool]) }

    it "returns nil for non-hash input" do
      expect(registry.resolve("nope")).to be_nil
    end

    it "returns nil for unknown tool" do
      expect(registry.resolve({ "tool" => "missing" })).to be_nil
    end

    it "returns tool and stringified args for string keys" do
      action = registry.resolve({ "tool" => "ping", "args" => { "x" => 1 } })
      expect(action[:tool]).to eq(sample_tool)
      expect(action[:args]).to eq({ "x" => 1 })
    end

    it "accepts symbol keys" do
      action = registry.resolve({ tool: "ping", args: { x: 2 } })
      expect(action[:args]).to eq({ "x" => 2 })
    end

    it "defaults missing args to empty hash" do
      action = registry.resolve({ "tool" => "ping" })
      expect(action[:args]).to eq({})
    end
  end

  describe "#descriptions_for_prompt" do
    it "includes name, description, and JSON schema" do
      registry = described_class.new([sample_tool])
      text = registry.descriptions_for_prompt
      expect(text).to include("ping")
      expect(text).to include("pong")
      expect(text).to include('"type":"object"')
    end
  end
end

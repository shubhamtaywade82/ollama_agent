# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ollama_agent/tools/registry"

RSpec.describe OllamaAgent::Tools::Registry do
  before { described_class.reset! }
  after  { described_class.reset! }

  describe ".register and .execute_custom" do
    it "executes a registered custom tool handler" do
      described_class.register("my_tool",
        schema: { type: "object", properties: {}, required: [] }
      ) { |args, root:, read_only:| "result:#{args["x"]}" }

      result = described_class.execute_custom("my_tool", { "x" => "42" }, root: "/tmp", read_only: false)
      expect(result).to eq("result:42")
    end

    it "returns an error message for an unknown custom tool" do
      result = described_class.execute_custom("nope", {}, root: "/tmp", read_only: false)
      expect(result).to include("Unknown custom tool")
    end

    it "reports custom_tool? correctly" do
      expect(described_class.custom_tool?("my_tool")).to be false
      described_class.register("my_tool", schema: {}) { "x" }
      expect(described_class.custom_tool?("my_tool")).to be true
    end

    it "passes read_only: true through to the handler" do
      received_read_only = nil
      described_class.register("check_ro", schema: {}) do |_args, root:, read_only:|
        received_read_only = read_only
        "ok"
      end
      described_class.execute_custom("check_ro", {}, root: "/tmp", read_only: true)
      expect(received_read_only).to be true
    end
  end

  describe ".custom_schemas" do
    it "returns tool schemas in ollama tool format" do
      described_class.register("do_thing",
        schema: { description: "does a thing", properties: { x: { type: "string" } }, required: ["x"] }
      ) { "ok" }

      schemas = described_class.custom_schemas
      expect(schemas.size).to eq(1)
      expect(schemas.first[:type]).to eq("function")
      expect(schemas.first.dig(:function, :name)).to eq("do_thing")
    end

    it "returns empty array when no custom tools registered" do
      expect(described_class.custom_schemas).to eq([])
    end
  end

  describe ".reset!" do
    it "clears all registrations" do
      described_class.register("t", schema: {}) { "x" }
      described_class.reset!
      expect(described_class.custom_tool?("t")).to be false
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::ToolRuntime::Memory do
  describe "#append and #recent" do
    it "stores steps in order" do
      memory = described_class.new(limit: 10)
      memory.append(thought: { "tool" => "a" }, action: { tool: :t }, result: "ok")

      expect(memory.recent.size).to eq(1)
      expect(memory.recent.last[:thought]).to eq({ "tool" => "a" })
      expect(memory.recent.last[:result]).to eq("ok")
    end

    it "drops oldest entries when over limit" do
      memory = described_class.new(limit: 2)
      memory.append(thought: { "n" => 1 }, action: {}, result: "a")
      memory.append(thought: { "n" => 2 }, action: {}, result: "b")
      memory.append(thought: { "n" => 3 }, action: {}, result: "c")

      expect(memory.recent.map { |s| s[:result] }).to eq(%w[b c])
    end

    it "treats limit below 1 as 1" do
      memory = described_class.new(limit: 0)
      memory.append(thought: {}, action: {}, result: "x")
      memory.append(thought: {}, action: {}, result: "y")

      expect(memory.recent.map { |s| s[:result] }).to eq(["y"])
    end
  end

  describe "#tool_descriptions_for_prompt" do
    it "returns empty string when unset" do
      expect(described_class.new.tool_descriptions_for_prompt).to eq("")
    end

    it "returns injected text" do
      memory = described_class.new
      memory.tool_descriptions = "extra hint"
      expect(memory.tool_descriptions_for_prompt).to eq("extra hint")
    end
  end
end

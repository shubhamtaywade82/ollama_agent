# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::MemorySearch do
  let(:tool) { described_class.new }
  let(:memory_manager) { instance_double(OllamaAgent::Memory::Manager) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("memory_search")
    end

    it "is read_only safe" do
      expect(tool.read_only_safe).to be(true)
    end
  end

  describe "#call" do
    it "returns no-memories message when nothing matches" do
      allow(memory_manager).to receive(:search).and_return({})
      result = tool.call({ "query" => "nonexistent" }, context: { memory_manager: memory_manager })
      expect(result).to match(/No memories/)
    end

    it "returns matching entries" do
      allow(memory_manager).to receive(:search).and_return({ "arch/decision" => "use clean architecture" })
      result = tool.call({ "query" => "architecture" }, context: { memory_manager: memory_manager })
      expect(result).to include("arch/decision")
    end

    it "returns error without memory manager" do
      result = tool.call({ "query" => "x" }, context: {})
      expect(result).to match(/no memory manager/)
    end
  end
end

RSpec.describe OllamaAgent::Tools::SessionSummary do
  let(:tool) { described_class.new }
  let(:memory_manager) { instance_double(OllamaAgent::Memory::Manager) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("session_summary")
    end
  end

  describe "#call" do
    it "returns recent context entries" do
      entries = [
        { type: :tool_call, content: { tool: "read_file" } },
        { type: :tool_result, content: { tool: "read_file", result: "ok" } }
      ]
      allow(memory_manager).to receive(:recent_context).and_return(entries)
      result = tool.call({}, context: { memory_manager: memory_manager })
      expect(result[:entries]).to eq(2)
    end

    it "returns no-activity message when empty" do
      allow(memory_manager).to receive(:recent_context).and_return([])
      result = tool.call({}, context: { memory_manager: memory_manager })
      expect(result).to match(/No recent/)
    end

    it "returns error without memory manager" do
      result = tool.call({}, context: {})
      expect(result).to match(/no memory manager/)
    end
  end
end

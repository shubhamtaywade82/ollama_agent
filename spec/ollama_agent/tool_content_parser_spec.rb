# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::ToolContentParser do
  describe ".synthetic_calls" do
    it "returns empty when disabled" do
      ENV.delete("OLLAMA_AGENT_PARSE_TOOL_JSON")
      expect(described_class.synthetic_calls('{"name":"read_file","parameters":{"path":"a"}}')).to eq([])
    end

    context "when OLLAMA_AGENT_PARSE_TOOL_JSON=1" do
      around do |example|
        ENV["OLLAMA_AGENT_PARSE_TOOL_JSON"] = "1"
        begin
          example.run
        ensure
          ENV.delete("OLLAMA_AGENT_PARSE_TOOL_JSON")
        end
      end

      it "parses JSON lines with name and parameters" do
        content = '{"name": "list_files", "parameters": {"directory":".","max_entries":"10"}}'
        calls = described_class.synthetic_calls(content)
        expect(calls.size).to eq(1)
        expect(calls.first.name).to eq("list_files")
        expect(calls.first.arguments).to include("directory" => ".")
      end

      it "ignores unknown tool names" do
        content = '{"name": "unknown_tool", "parameters": {}}'
        expect(described_class.synthetic_calls(content)).to eq([])
      end

      it "ignores invalid JSON lines" do
        expect(described_class.synthetic_calls("{not json")).to eq([])
      end
    end
  end
end

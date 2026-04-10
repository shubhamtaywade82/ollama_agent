# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::ToolRuntime::JsonExtractor do
  describe ".extract_object" do
    it "parses a bare object" do
      expect(described_class.extract_object('{"tool":"a","args":{}}')).to eq({ "tool" => "a", "args" => {} })
    end

    it "parses the first object when surrounded by prose" do
      text = 'Here you go: {"tool":"x","args":{"y":1}} thanks'
      expect(described_class.extract_object(text)).to eq({ "tool" => "x", "args" => { "y" => 1 } })
    end

    it "handles nested structures and braces inside strings" do
      text = '{"tool":"t","args":{"msg":"brace { not counted}"}}'
      expect(described_class.extract_object(text)["args"]["msg"]).to eq("brace { not counted}")
    end

    it "raises JsonParseError when no object starts" do
      expect { described_class.extract_object("no json here") }
        .to raise_error(OllamaAgent::ToolRuntime::JsonParseError, /no JSON object/)
    end

    it "raises JsonParseError for invalid JSON" do
      expect { described_class.extract_object("{not json}") }
        .to raise_error(OllamaAgent::ToolRuntime::JsonParseError, /invalid JSON/)
    end

    it "raises ArgumentError for non-string" do
      expect { described_class.extract_object(nil) }.to raise_error(ArgumentError)
    end
  end
end

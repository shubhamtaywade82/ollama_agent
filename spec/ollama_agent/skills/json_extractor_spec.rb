# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Skills::JsonExtractor do
  describe ".parse" do
    context "with bare JSON" do
      it "returns a hash with symbolized keys" do
        expect(described_class.parse('{"a": 1}')).to eq(a: 1)
      end
    end

    context "with leading prose" do
      it "extracts the first balanced object" do
        text = "Sure! Here it is: {\"name\": \"x\"} and more text"
        expect(described_class.parse(text)).to eq(name: "x")
      end
    end

    context "with a fenced ```json block" do
      it "extracts the fenced JSON" do
        text = "before\n```json\n{\"k\": [1,2]}\n```\nafter"
        expect(described_class.parse(text)).to eq(k: [1, 2])
      end
    end

    context "with brackets inside string literals" do
      it "ignores them when balancing" do
        text = '{"snippet": "if (x) { y }", "ok": true}'
        expect(described_class.parse(text)).to eq(snippet: "if (x) { y }", ok: true)
      end
    end

    context "with nested objects" do
      it "captures the full balanced span" do
        expect(described_class.parse('text {"a": {"b": 1}} trailing')).to eq(a: { b: 1 })
      end
    end

    context "with empty input" do
      it "raises ExtractionError" do
        expect { described_class.parse("   ") }
          .to raise_error(described_class::ExtractionError, /empty/)
      end
    end

    context "with no JSON present" do
      it "raises ExtractionError" do
        expect { described_class.parse("plain prose, no json here") }
          .to raise_error(described_class::ExtractionError, /no JSON/)
      end
    end

    context "with malformed JSON" do
      it "raises ExtractionError with parser detail" do
        expect { described_class.parse('{"bad": ,}') }
          .to raise_error(described_class::ExtractionError, /invalid JSON/)
      end
    end
  end
end

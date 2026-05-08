# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Topology::SymbolIdentity do
  let(:fqcn) { "Animals::Cat" }
  let(:signature) do
    {
      fqcn: fqcn,
      methods: [
        { name: "b", kind: "instance", parameters: [{ kind: "positional", name: "x" }] },
        { name: "a", kind: "instance", parameters: [] }
      ]
    }
  end

  it "returns the same id for the same fqcn, signature, and extractor version" do
    a = described_class.compute(fqcn: fqcn, signature: signature, extractor_version: "1.0.0")
    b = described_class.compute(fqcn: fqcn, signature: signature, extractor_version: "1.0.0")
    expect(a).to eq(b)
    expect(a.length).to eq(64)
  end

  it "changes the id when extractor_version changes" do
    a = described_class.compute(fqcn: fqcn, signature: signature, extractor_version: "1.0.0")
    b = described_class.compute(fqcn: fqcn, signature: signature, extractor_version: "1.0.1")
    expect(a).not_to eq(b)
  end

  it "is stable when methods are reordered in the raw signature hash" do
    reordered = {
      fqcn: fqcn,
      methods: signature[:methods].reverse
    }
    a = described_class.compute(fqcn: fqcn, signature: signature, extractor_version: "1.0.0")
    b = described_class.compute(fqcn: fqcn, signature: reordered, extractor_version: "1.0.0")
    expect(a).to eq(b)
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Topology::SignatureNormalizer do
  it "sorts methods alphabetically so source order does not affect class signatures" do
    a_first = {
      fqcn: "Foo",
      methods: [
        { name: "a", kind: "instance", parameters: [] },
        { name: "m", kind: "instance", parameters: [] }
      ]
    }
    m_first = {
      fqcn: "Foo",
      methods: [
        { name: "m", kind: "instance", parameters: [] },
        { name: "a", kind: "instance", parameters: [] }
      ]
    }
    expect(described_class.normalize_class(class_fqcn: a_first[:fqcn], methods: a_first[:methods]))
      .to eq(described_class.normalize_class(class_fqcn: m_first[:fqcn], methods: m_first[:methods]))
  end

  it "canonicalizes parameters by kind bucket then name and strips defaults" do
    raw = {
      name: "foo",
      kind: "instance",
      parameters: [
        { kind: "keyword_optional", name: "z", default: 1 },
        { kind: "positional", name: "a" },
        { kind: "keyword_required", name: "k" }
      ]
    }
    out = described_class.normalize(raw)
    kinds = out["parameters"].map { |p| p["kind"] }
    expect(kinds).to eq(%w[positional keyword_required keyword_optional])
    expect(out["parameters"].none? { |p| p.key?("default") }).to be(true)
  end
end

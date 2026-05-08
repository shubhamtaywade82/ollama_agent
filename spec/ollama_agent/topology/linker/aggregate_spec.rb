# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Topology::Linker::Aggregate do
  it "merges class reopens across files into one FQCN entry" do
    a = File.join("/tmp", "a.rb")
    b = File.join("/tmp", "b.rb")
    n1 = OllamaAgent::Topology::IR::ClassNode.build(
      source_path: a,
      source_line: 1,
      origin_extractor_version: "1.0.0",
      fqcn: "Widget",
      methods: [{ name: "first", kind: "instance", parameters: [] }]
    )
    n2 = OllamaAgent::Topology::IR::ClassNode.build(
      source_path: b,
      source_line: 1,
      origin_extractor_version: "1.0.0",
      fqcn: "Widget",
      methods: [{ name: "second", kind: "instance", parameters: [] }]
    )
    agg = described_class.new.call(
      ir_by_file: {
        a => [n1],
        b => [n2]
      }
    )
    names = agg["Widget"][:methods].map { |m| m[:name] || m["name"] }
    expect(names).to contain_exactly("first", "second")
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Topology::StagedGraph do
  let(:graph) { described_class.new }
  let(:node) do
    OllamaAgent::Topology::IR::ClassNode.build(
      source_path: "/tmp/a.rb",
      source_line: 1,
      origin_extractor_version: "1.0.0",
      fqcn: "Foo",
      methods: [{ name: "bar", kind: "instance", parameters: [] }]
    )
  end

  it "moves staged origins into committed storage on promote" do
    fp = "/tmp/a.rb"
    graph.stage(file_path: fp, ir_nodes: [node])
    sid = OllamaAgent::Topology::SymbolIdentity.compute(
      fqcn: "Foo",
      signature: { fqcn: "Foo", methods: node.methods.map(&:dup) },
      extractor_version: node.origin_extractor_version
    )
    expect(graph.promote(file_path: fp)).to eq(:promoted)
    expect(graph.staged_origins_for(symbol_id: sid)).to be_empty
    expect(graph.committed_origins_for(symbol_id: sid).size).to eq(1)
  end

  it "keeps parse-failed files out of committed storage" do
    fp = "/tmp/bad.rb"
    graph.note_parse_failure(file_path: fp)
    expect(graph.promote(file_path: fp)).to eq(:rejected_parse_error)
  end

  it "returns rejected_validation and leaves staged data when validation is blocked" do
    fp = "/tmp/c.rb"
    graph.stage(file_path: fp, ir_nodes: [node])
    graph.note_validation_failure(file_path: fp)
    expect(graph.promote(file_path: fp)).to eq(:rejected_validation)
    sid = OllamaAgent::Topology::SymbolIdentity.compute(
      fqcn: "Foo",
      signature: { fqcn: "Foo", methods: node.methods.map(&:dup) },
      extractor_version: node.origin_extractor_version
    )
    expect(graph.committed_origins_for(symbol_id: sid)).to be_empty
    expect(graph.staged_origins_for(symbol_id: sid).size).to eq(1)
  end

  it "removes staged entries on reject" do
    fp = "/tmp/d.rb"
    graph.stage(file_path: fp, ir_nodes: [node])
    graph.reject(file_path: fp, reason: :user_cancel)
    sid = OllamaAgent::Topology::SymbolIdentity.compute(
      fqcn: "Foo",
      signature: { fqcn: "Foo", methods: node.methods.map(&:dup) },
      extractor_version: node.origin_extractor_version
    )
    expect(graph.staged_origins_for(symbol_id: sid)).to be_empty
  end
end

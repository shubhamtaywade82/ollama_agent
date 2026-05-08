# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Topology::SymbolGraph do
  let(:graph) { described_class.new }
  let(:node_a) do
    OllamaAgent::Topology::IR::ClassNode.build(
      source_path: "a.rb",
      source_line: 1,
      origin_extractor_version: "1.0.0",
      fqcn: "Foo",
      methods: [{ name: "x", kind: "instance", parameters: [] }]
    )
  end

  it "records multiple origins for the same symbol id" do
    sid = "sym-1"
    expect(graph.add_origin(symbol_id: sid, file_path: "one.rb", ir_node: node_a)).to be(true)
    expect(graph.add_origin(symbol_id: sid, file_path: "two.rb", ir_node: node_a)).to be(true)
    paths = graph.origins_for(symbol_id: sid).map { |o| o[:file_path] }
    expect(paths).to contain_exactly("one.rb", "two.rb")
  end

  it "returns false on idempotent duplicate origins" do
    sid = "sym-2"
    graph.add_origin(symbol_id: sid, file_path: "f.rb", ir_node: node_a)
    expect(graph.add_origin(symbol_id: sid, file_path: "f.rb", ir_node: node_a)).to be(false)
  end

  it "reset_file removes only matching origins" do
    sid = "sym-3"
    graph.add_origin(symbol_id: sid, file_path: "keep.rb", ir_node: node_a)
    graph.add_origin(symbol_id: sid, file_path: "drop.rb", ir_node: node_a)
    removed = graph.reset_file(file_path: "drop.rb")
    expect(removed).to eq(1)
    expect(graph.origins_for(symbol_id: sid).map { |o| o[:file_path] }).to eq(["keep.rb"])
  end
end

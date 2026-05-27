# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Synthesis::RouteSynthesizer do
  it "emits deterministic resources blocks sorted by controller fqcn" do
    graph = OllamaAgent::Topology::StagedGraph.new
    zeta = OllamaAgent::Topology::IR::ClassNode.build(
      source_path: "/z.rb",
      source_line: 1,
      origin_extractor_version: "1.0.0",
      fqcn: "ZetaController",
      superclass_fqcn: nil,
      methods: [{ name: "index", kind: "instance", parameters: [] }]
    )
    alpha = OllamaAgent::Topology::IR::ClassNode.build(
      source_path: "/a.rb",
      source_line: 1,
      origin_extractor_version: "1.0.0",
      fqcn: "AlphaController",
      superclass_fqcn: nil,
      methods: [{ name: "show", kind: "instance", parameters: [] }]
    )
    graph.add_origin(symbol_id: "z", file_path: "/z.rb", ir_node: zeta)
    graph.add_origin(symbol_id: "a", file_path: "/a.rb", ir_node: alpha)

    extractor = OllamaAgent::Synthesis::IntegrationExtractor.new(staged_graph: graph)
    synth = described_class.new(integration_extractor: extractor)
    first = synth.synthesize
    second = synth.synthesize
    expect(first).to eq(second)
    expect(first).to include("resources :alpha")
    expect(first).to include("resources :zeta")
    expect(first.index("resources :alpha")).to be < first.index("resources :zeta")
  end

  it "wraps namespaced controllers" do
    graph = OllamaAgent::Topology::StagedGraph.new
    ctl = OllamaAgent::Topology::IR::ClassNode.build(
      source_path: "/admin/posts_controller.rb",
      source_line: 1,
      origin_extractor_version: "1.0.0",
      fqcn: "Admin::PostsController",
      superclass_fqcn: nil,
      methods: [{ name: "index", kind: "instance", parameters: [] }]
    )
    graph.add_origin(symbol_id: "adm", file_path: "/admin/posts_controller.rb", ir_node: ctl)
    extractor = OllamaAgent::Synthesis::IntegrationExtractor.new(staged_graph: graph)
    out = described_class.new(integration_extractor: extractor).synthesize
    expect(out).to include("namespace :admin do")
    expect(out).to include("resources :posts")
    expect(out).to include("end")
  end
end

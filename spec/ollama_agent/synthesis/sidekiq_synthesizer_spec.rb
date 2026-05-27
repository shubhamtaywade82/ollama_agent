# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Synthesis::SidekiqSynthesizer do
  def worker_node(path, fqcn, queue)
    OllamaAgent::Topology::IR::WorkerNode.build(
      source_path: path,
      source_line: 1,
      origin_extractor_version: "1.0.0",
      fqcn: fqcn,
      queue: queue,
      perform_signature: {}
    )
  end

  let(:rows) do
    [
      { id: "1", path: "/hi.rb", fqcn: "HiWorker", queue: "critical" },
      { id: "2", path: "/lo.rb", fqcn: "LoWorker", queue: "default" },
      { id: "3", path: "/zz.rb", fqcn: "ZzWorker", queue: "critical" }
    ]
  end

  let(:graph) do
    OllamaAgent::Topology::StagedGraph.new.tap do |g|
      rows.each do |r|
        w = worker_node(r[:path], r[:fqcn], r[:queue])
        g.add_origin(symbol_id: r[:id], file_path: r[:path], ir_node: w)
      end
    end
  end

  it "groups workers by queue with sorted fqcn lists" do
    extractor = OllamaAgent::Synthesis::IntegrationExtractor.new(staged_graph: graph)
    out = described_class.new(integration_extractor: extractor).synthesize
    expect(out.keys).to eq(%w[critical default])
    expect(out["critical"]).to eq(%w[HiWorker ZzWorker])
    expect(out["default"]).to eq(["LoWorker"])
  end
end

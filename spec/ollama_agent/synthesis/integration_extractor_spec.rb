# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Synthesis::IntegrationExtractor do
  def build_class(path, fqcn, **opts)
    OllamaAgent::Topology::IR::ClassNode.build(
      source_path: path,
      source_line: 1,
      origin_extractor_version: "1.0.0",
      fqcn: fqcn,
      **opts
    )
  end

  let(:post) do
    build_class("/app/models/post.rb", "Post", superclass_fqcn: "ApplicationRecord", methods: [])
  end

  let(:worker) do
    build_class(
      "/app/workers/notify_worker.rb",
      "NotifyWorker",
      superclass_fqcn: nil,
      includes: ["Sidekiq::Worker"],
      methods: [{ name: "perform", kind: "instance", parameters: [] }]
    )
  end

  let(:controller) do
    build_class(
      "/app/controllers/posts_controller.rb",
      "PostsController",
      superclass_fqcn: "ApplicationController",
      methods: [
        { name: "index", kind: "instance", parameters: [] },
        { name: "show", kind: "instance", parameters: [] }
      ]
    )
  end

  let(:committed_fixture_graph) do
    OllamaAgent::Topology::StagedGraph.new.tap do |g|
      g.add_origin(symbol_id: "sym_post", file_path: "/app/models/post.rb", ir_node: post)
      g.add_origin(symbol_id: "sym_worker", file_path: "/app/workers/notify_worker.rb", ir_node: worker)
      g.add_origin(symbol_id: "sym_ctl", file_path: "/app/controllers/posts_controller.rb", ir_node: controller)
    end
  end

  it "buckets AR models, Sidekiq workers, and inferred routes from committed origins only" do
    scan = described_class.new(staged_graph: committed_fixture_graph).extract
    expect(scan.ar_models.map(&:fqcn)).to eq(["Post"])
    expect(scan.workers.map(&:fqcn)).to eq(["NotifyWorker"])
    expect(scan.routes.map(&:action_name).uniq.sort).to eq(%w[index show])
    expect(scan.routes.first.controller_fqcn).to eq("PostsController")
  end
end

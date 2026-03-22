# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::RubyIndex do
  let(:fixture_root) { File.expand_path("../fixtures/ruby_index", __dir__) }

  describe ".build" do
    it "indexes classes, modules, and methods from fixture Ruby" do
      idx = described_class.build(root: fixture_root)

      expect(idx.files_indexed).to eq(1)
      names = idx.constants.map { |r| r[:name] }
      expect(names).to include("Outer", "Outer::Inner")

      methods = idx.methods.map { |r| [r[:name], r[:namespace], r[:singleton]] }
      expect(methods).to include(["instance_method", "Outer::Inner", false])
      expect(methods).to include(["singleton_method", "Outer::Inner", true])
      expect(methods).to include(["meta", "Outer::Inner", true])
      expect(methods.map(&:first)).to include("top_level_method")
    end

    it "finds methods by substring" do
      idx = described_class.build(root: fixture_root)
      hits = idx.search_method("instance")
      expect(hits.size).to eq(1)
      expect(hits.first[:name]).to eq("instance_method")
    end
  end

  describe "cache concurrency (via Agent)" do
    let(:fixture_root) { File.expand_path("../fixtures/ruby_index", __dir__) }

    it "calls RubyIndex.build only once when ruby_index is invoked concurrently" do
      ENV["OLLAMA_AGENT_INDEX_REBUILD"] = "1"
      calls = 0
      allow(described_class).to receive(:build).and_wrap_original do |orig, **kwargs|
        calls += 1
        sleep 0.02
        orig.call(**kwargs)
      end

      agent = OllamaAgent::Agent.new(root: fixture_root, confirm_patches: false)
      threads = 8.times.map { Thread.new { agent.send(:ruby_index) } }
      threads.each(&:join)

      expect(calls).to eq(1)
    ensure
      ENV.delete("OLLAMA_AGENT_INDEX_REBUILD")
    end
  end
end

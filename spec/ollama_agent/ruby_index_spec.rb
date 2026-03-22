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
end

# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::Runtime::FencingAllocator do
  describe "#allocate" do
    it "returns monotonic gapless tokens per scope" do
      Dir.mktmpdir("fencing") do |root|
        registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
        allocator = described_class.new(registry.runtime)

        expect(allocator.allocate(scope: "s1")).to eq(1)
        expect(allocator.allocate(scope: "s1")).to eq(2)
        expect(allocator.allocate(scope: "s2")).to eq(1)
      end
    end
  end
end

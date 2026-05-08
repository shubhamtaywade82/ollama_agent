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

    it "supports allocate_joining inside an existing immediate transaction" do
      Dir.mktmpdir("fencing-join") do |root|
        registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
        db = registry.runtime
        allocator = described_class.new(db)
        db.transaction(:immediate) do
          expect(allocator.allocate_joining(scope: "s9")).to eq(1)
          expect(allocator.allocate_joining(scope: "s9")).to eq(2)
        end
        expect(allocator.allocate(scope: "s9")).to eq(3)
      end
    end
  end
end

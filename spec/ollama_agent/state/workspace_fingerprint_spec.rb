# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::State::WorkspaceFingerprint do
  describe "#compute" do
    it "is deterministic for equivalent trees" do
      first_digest = nil
      second_digest = nil

      Dir.mktmpdir("fingerprint-a") do |workspace|
        RuntimeKernelHarness.write_file(workspace, "a.txt", "alpha")
        RuntimeKernelHarness.write_file(workspace, "b/c.txt", "beta")
        first_digest = described_class.new(root: workspace).compute
      end

      Dir.mktmpdir("fingerprint-b") do |workspace|
        RuntimeKernelHarness.write_file(workspace, "b/c.txt", "beta")
        RuntimeKernelHarness.write_file(workspace, "a.txt", "alpha")
        second_digest = described_class.new(root: workspace).compute
      end

      expect(second_digest).to eq(first_digest)
    end

    it "does not conflate path boundaries (lib/sample.rb vs lib/sample + .rb prefix)" do
      collision_a = nil
      collision_b = nil

      Dir.mktmpdir("fingerprint-collision-a") do |workspace|
        RuntimeKernelHarness.write_file(workspace, "lib/sample.rb", "X")
        collision_a = described_class.new(root: workspace).compute
      end

      Dir.mktmpdir("fingerprint-collision-b") do |workspace|
        RuntimeKernelHarness.write_file(workspace, "lib/sample", ".rbX")
        collision_b = described_class.new(root: workspace).compute
      end

      expect(collision_b).not_to eq(collision_a)
    end
  end
end

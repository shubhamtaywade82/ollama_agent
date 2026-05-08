# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::Security::ResourceGuard do
  describe "#allow?" do
    it "allows paths rooted inside the configured workspace" do
      Dir.mktmpdir("resource-guard") do |workspace|
        allowed_file = File.join(workspace, "lib", "safe.rb")
        RuntimeKernelHarness.write_file(workspace, "lib/safe.rb", "puts :safe")

        guard = described_class.new(root: workspace)

        expect(guard.allow?(allowed_file)).to be(true)
      end
    end

    it "rejects paths outside the configured workspace" do
      Dir.mktmpdir("resource-guard") do |workspace|
        guard = described_class.new(root: workspace)

        expect(guard.allow?("/tmp/not-allowed.txt")).to be(false)
      end
    end

    it "allows a new file path when its parent directory exists inside the workspace" do
      Dir.mktmpdir("resource-guard-new-file") do |workspace|
        RuntimeKernelHarness.write_file(workspace, "lib/existing.rb", "x")
        guard = described_class.new(root: workspace)
        new_file = File.join(workspace, "lib", "brand_new.rb")

        expect(guard.allow?(new_file)).to be(true)
      end
    end

    it "rejects paths outside the workspace even when expressed relative to cwd" do
      Dir.mktmpdir("resource-guard-escape") do |workspace|
        RuntimeKernelHarness.write_file(workspace, "lib/x.rb", "x")
        guard = described_class.new(root: workspace)
        sibling = File.join(File.dirname(workspace), "sibling-outside", "f.txt")

        expect(guard.allow?(sibling)).to be(false)
      end
    end

    it "rejects paths reached via symlink pointing outside the workspace" do
      skip "symlink not supported" unless File.respond_to?(:symlink)

      Dir.mktmpdir("resource-guard-outside") do |outside|
        Dir.mktmpdir("resource-guard-workspace") do |workspace|
          File.write(File.join(outside, "secret.txt"), "nope")
          link = File.join(workspace, "escape")
          begin
            File.symlink(outside, link)
          rescue Errno::EPERM, NotImplementedError
            skip "symlink not permitted"
          end

          guard = described_class.new(root: workspace)

          expect(guard.allow?(File.join(link, "secret.txt"))).to be(false)
        end
      end
    end
  end
end

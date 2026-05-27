# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuntimeKernelHarness do
  describe ".tree_digest" do
    it "returns the same digest for the same tree content" do
      first_digest = nil
      second_digest = nil

      described_class.with_workspace do |workspace|
        described_class.write_file(workspace, "lib/sample.rb", "class Sample; end\n")
        described_class.write_file(workspace, "README.md", "hello\n")
        first_digest = described_class.tree_digest(workspace)
      end

      described_class.with_workspace do |workspace|
        described_class.write_file(workspace, "README.md", "hello\n")
        described_class.write_file(workspace, "lib/sample.rb", "class Sample; end\n")
        second_digest = described_class.tree_digest(workspace)
      end

      expect(second_digest).to eq(first_digest)
    end
  end
end

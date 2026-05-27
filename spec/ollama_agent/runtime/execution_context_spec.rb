# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::ExecutionContext do
  describe "#initialize" do
    it "accepts a supported mode and exposes immutable metadata" do
      context = described_class.new(
        mode: "normal",
        workspace_root: "/tmp/workspace",
        manifest_id: "manifest-1",
        metadata: { "attempt" => 1 }
      )

      expect(context.mode).to eq("normal")
      expect(context.metadata).to eq({ "attempt" => 1 })
      expect(context.metadata).to be_frozen
    end

    it "rejects unsupported modes" do
      expect do
        described_class.new(mode: "invalid", workspace_root: "/tmp", manifest_id: "manifest-1")
      end.to raise_error(ArgumentError, "invalid execution mode: invalid")
    end
  end
end

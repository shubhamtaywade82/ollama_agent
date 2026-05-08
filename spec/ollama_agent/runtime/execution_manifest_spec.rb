# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::ExecutionManifest do
  describe "#to_h" do
    it "returns a manifest hash with lineage and fingerprint fields" do
      manifest = described_class.new(
        parent_manifest_id: "parent-1",
        workspace_fingerprint: "fingerprint-1",
        metadata: { "mode" => "normal" },
        id: "manifest-1",
        created_at: "2026-05-08T00:00:00Z"
      )

      expect(manifest.to_h).to eq(
        {
          "id" => "manifest-1",
          "parent_manifest_id" => "parent-1",
          "workspace_fingerprint" => "fingerprint-1",
          "created_at" => "2026-05-08T00:00:00Z",
          "metadata" => { "mode" => "normal" }
        }
      )
    end

    it "accepts created_at from a logical clock (no wall clock default)" do
      clock = OllamaAgent::Runtime::LogicalClock.new(epoch: 0)
      manifest = described_class.new(
        parent_manifest_id: nil,
        workspace_fingerprint: "fp",
        created_at: clock.next_stamp,
        id: "m-1"
      )

      expect(manifest.created_at).to eq("0:1")
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::State::ReentryPacket do
  describe "#to_h" do
    it "returns a stable hash payload with sorted changed files" do
      packet = described_class.new(
        reason: "planner_invalid_json",
        workspace_fingerprint: "fingerprint-1",
        changed_files: ["b.rb", "a.rb"],
        summary: "Escalated once and resumed"
      )

      expect(packet.to_h).to eq(
        {
          "reason" => "planner_invalid_json",
          "workspace_fingerprint" => "fingerprint-1",
          "changed_files" => ["a.rb", "b.rb"],
          "summary" => "Escalated once and resumed"
        }
      )
    end
  end
end

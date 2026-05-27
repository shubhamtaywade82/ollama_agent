# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::Runtime::IntegrationQueue do
  describe "#enqueue, #claim_next, #mark_done" do
    it "moves items pending -> claimed -> done" do
      Dir.mktmpdir("integration-queue") do |root|
        registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
        queue = described_class.new(registry.runtime)

        queue.enqueue(manifest_id: "m1", payload: "job-a", created_at: "0:1")
        queue.enqueue(manifest_id: "m1", payload: "job-b", created_at: "0:2")

        first = queue.claim_next
        expect(first["status"]).to eq("claimed")
        expect(first["payload"]).to eq("job-a")

        second = queue.claim_next
        expect(second["payload"]).to eq("job-b")

        expect(queue.claim_next).to be_nil

        queue.mark_done(id: first["id"])
        row = registry.runtime.get_first_row(
          "SELECT status FROM integration_queue WHERE id = ?",
          [first["id"]]
        )
        expect(row["status"]).to eq("done")
      end
    end
  end
end

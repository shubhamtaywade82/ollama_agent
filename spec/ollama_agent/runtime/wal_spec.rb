# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::Runtime::WAL do
  describe "#replay" do
    it "yields only mutation kind events in order" do
      Dir.mktmpdir("wal-spec") do |root|
        registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
        es = OllamaAgent::Runtime::EventStore.new(registry.event_store)
        wal = described_class.new(es)

        es.append(manifest_id: "m1", logical_stamp: "0:1", kind: "mutation", payload: "m1")
        es.append(manifest_id: "m1", logical_stamp: "0:2", kind: "meta", payload: "noise")
        es.append(manifest_id: "m1", logical_stamp: "0:3", kind: "mutation", payload: "m2")

        payloads = wal.replay(manifest_id: "m1").map { |r| r["payload"] }
        expect(payloads).to eq(%w[m1 m2])
      end
    end
  end
end

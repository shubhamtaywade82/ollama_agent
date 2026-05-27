# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::Runtime::WAL do
  describe "E1 M1 storage replay acceptance" do
    it "preserves mutation order on replay and treats duplicate intent_hash as no-op" do
      Dir.mktmpdir("storage-replay") do |root|
        registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
        clock = OllamaAgent::Runtime::LogicalClock.new
        store = OllamaAgent::Runtime::EventStore.new(registry.event_store)
        wal = described_class.new(store)
        manifest_id = "manifest-e1"

        expect(
          wal.append_mutation(
            manifest_id: manifest_id,
            logical_stamp: clock.next_stamp,
            payload: "first",
            intent_hash: "intent-a"
          )
        ).to eq(:inserted)

        expect(
          wal.append_mutation(
            manifest_id: manifest_id,
            logical_stamp: clock.next_stamp,
            payload: "second",
            intent_hash: "intent-b"
          )
        ).to eq(:inserted)

        expect(
          wal.append_mutation(
            manifest_id: manifest_id,
            logical_stamp: clock.next_stamp,
            payload: "duplicate-body",
            intent_hash: "intent-a"
          )
        ).to eq(:duplicate)

        replayed = wal.replay(manifest_id: manifest_id).to_a
        expect(replayed.map { |r| r["payload"] }).to eq(%w[first second])
        expect(replayed.map { |r| r["id"] }).to eq([1, 2])

        total = 0
        store.each_for(manifest_id: manifest_id) { total += 1 }
        expect(total).to eq(2)
      end
    end
  end
end

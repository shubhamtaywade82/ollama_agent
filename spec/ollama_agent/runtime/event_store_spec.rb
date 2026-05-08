# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::Runtime::EventStore do
  let(:clock) { OllamaAgent::Runtime::LogicalClock.new }

  def store_for_tmpdir
    Dir.mktmpdir("event-store") do |root|
      registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
      yield described_class.new(registry.event_store)
    end
  end

  describe "#append and #each_for" do
    it "appends rows and iterates in id order" do
      store_for_tmpdir do |store|
        expect(
          store.append(
            manifest_id: "m1",
            logical_stamp: clock.next_stamp,
            kind: "mutation",
            payload: "a"
          )
        ).to eq(:inserted)

        expect(
          store.append(
            manifest_id: "m1",
            logical_stamp: clock.next_stamp,
            kind: "mutation",
            payload: "b"
          )
        ).to eq(:inserted)

        rows = []
        store.each_for(manifest_id: "m1") { |r| rows << r }

        expect(rows.map { |r| r["payload"] }).to eq(%w[a b])
        expect(rows.map { |r| r["id"] }).to eq([1, 2])
      end
    end

    it "returns :duplicate for repeated intent_hash without inserting" do
      store_for_tmpdir do |store|
        store.append(
          manifest_id: "m1",
          logical_stamp: "0:1",
          kind: "mutation",
          payload: "x",
          intent_hash: "same"
        )
        expect(
          store.append(
            manifest_id: "m1",
            logical_stamp: "0:2",
            kind: "mutation",
            payload: "y",
            intent_hash: "same"
          )
        ).to eq(:duplicate)

        count = 0
        store.each_for(manifest_id: "m1") { count += 1 }
        expect(count).to eq(1)
      end
    end

    it "round-trips binary payloads (NUL and high bytes) through WAL replay" do
      Dir.mktmpdir("event-store-binary") do |root|
        registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
        store = described_class.new(registry.event_store)
        wal = OllamaAgent::Runtime::WAL.new(store)
        binary = "\x00\xFF\x10binary".b

        expect(
          wal.append_mutation(
            manifest_id: "m-bin",
            logical_stamp: "0:1",
            payload: binary,
            intent_hash: "bin-1"
          )
        ).to eq(:inserted)

        row = wal.replay(manifest_id: "m-bin").first
        expect(row["payload"].b).to eq(binary)
      end
    end
  end
end

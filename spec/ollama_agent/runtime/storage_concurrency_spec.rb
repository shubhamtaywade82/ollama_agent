# frozen_string_literal: true

require "spec_helper"
require "sqlite3"
require "tmpdir"

RSpec.describe OllamaAgent::Runtime::EventStore, :concurrency do
  it "inserts 2048 events with gapless ids and per-thread monotonic id order" do
    Dir.mktmpdir("event-store-concurrency") do |root|
      OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root).event_store
      event_path = File.join(root, ".ollama_agent", "kernel", "event_store.db")
      clock = OllamaAgent::Runtime::LogicalClock.new
      manifest_id = "m-concurrent"

      threads = 8.times.map do |tid|
        Thread.new do
          db = SQLite3::Database.new(event_path)
          db.results_as_hash = true
          store = described_class.new(db)
          256.times do |seq|
            store.append(
              manifest_id: manifest_id,
              logical_stamp: clock.next_stamp,
              kind: "mutation",
              payload: "t#{tid}",
              intent_hash: "t#{tid.to_s.rjust(2, "0")}_#{seq.to_s.rjust(4, "0")}"
            )
          end
          db.close
        end
      end
      threads.each(&:join)

      verify_db = SQLite3::Database.new(event_path)
      verify_db.results_as_hash = true
      rows = []
      verify_db.execute(
        "SELECT id, intent_hash FROM events WHERE manifest_id = ? ORDER BY id ASC",
        [manifest_id]
      ) { |r| rows << r }
      verify_db.close

      expect(rows.length).to eq(2048)
      expect(rows.map { |r| r["id"] }).to eq((1..2048).to_a)

      8.times do |tid|
        prefix = "t#{tid.to_s.rjust(2, "0")}_"
        thread_rows = rows.select { |r| r["intent_hash"].start_with?(prefix) }
        expect(thread_rows.length).to eq(256)

        by_seq = thread_rows.map do |r|
          seq = r["intent_hash"].delete_prefix(prefix).to_i
          [seq, r["id"]]
        end.sort_by(&:first)
        expect(by_seq.map(&:first)).to eq((0...256).to_a)

        seq_ids = by_seq.map(&:last)
        expect(seq_ids.each_cons(2).all? { |a, b| a < b }).to be(true)
      end
    end
  end
end

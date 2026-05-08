# frozen_string_literal: true

require "json"
require "spec_helper"

RSpec.describe OllamaAgent::Runtime::Compactor do
  def insert_saga(db, manifest_id:, terminal:, last_epoch:, state: "committed")
    db.execute(
      "INSERT INTO sagas (manifest_id, state, intent_hash, planned_scopes, supervisor_lease, " \
      "last_transition_at_epoch, terminal, metadata) VALUES (?,?,?,?,?,?,?,?)",
      [manifest_id, state, nil, "[]", nil, last_epoch, terminal, nil]
    )
  end

  def insert_transition(db, manifest_id:, epoch:)
    db.execute(
      "INSERT INTO saga_transitions (manifest_id, from_state, to_state, reason, logical_stamp, created_at_epoch) " \
      "VALUES (?,?,?,?,?,?)",
      [manifest_id, "a", "b", nil, "#{epoch}:1", epoch]
    )
  end

  def insert_compensation(db, manifest_id:, pre_blob_sha:)
    db.execute(
      "INSERT INTO compensations (manifest_id, path, op, pre_blob_sha, pre_existed, fencing_token, logical_stamp, " \
      "applied) VALUES (?,?,?,?,?,?,?,?)",
      [manifest_id, "lib/x.rb", "restore", pre_blob_sha, 1, 1, "1:1", 0]
    )
  end

  def insert_event(db, manifest_id:, stamp:, kind: OllamaAgent::Runtime::EventStore::MUTATION_KIND, payload: "{}")
    db.execute(
      "INSERT INTO events (manifest_id, logical_stamp, kind, payload, intent_hash, created_at) VALUES (?,?,?,?,?,?)",
      [manifest_id, stamp, kind, payload, nil, stamp]
    )
  end

  # rubocop:disable RSpec/ExampleLength -- one integrated compaction scenario
  it "prunes terminal sagas, archives cold events, purges leases and intent rows, and removes orphan blobs" do
    Dir.mktmpdir("runtime-compactor") do |root|
      reg = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
      rt = reg.runtime
      es = reg.event_store
      bs = OllamaAgent::Runtime::BlobStore.new(kernel_dir: reg.kernel_dir)

      insert_saga(rt, manifest_id: "old-m", terminal: 1, last_epoch: 10)
      insert_transition(rt, manifest_id: "old-m", epoch: 10)

      insert_saga(rt, manifest_id: "act-m", terminal: 0, last_epoch: 900)
      keep_hex = bs.put("keep-bytes")
      insert_compensation(rt, manifest_id: "act-m", pre_blob_sha: keep_hex)
      payload = JSON.generate("op" => "atomic_write", "path" => "lib/x.rb", "sha256" => keep_hex)
      insert_event(es, manifest_id: "act-m", stamp: "900:1", payload: payload)

      insert_event(es, manifest_id: "old-m", stamp: "5:1", payload: "{}")

      drop_hex = bs.put("orphan-bytes")
      expect(File.exist?(bs.path_for_hex(drop_hex))).to be(true)

      rt.execute(
        "INSERT INTO intent_reservations (intent_hash, manifest_id, scopes, created_at_epoch) VALUES (?,?,?,?)",
        ["h1", "mid1", "[]", 1]
      )
      rt.execute(
        "INSERT INTO recovery_leases (manifest_id, holder, acquired_at_epoch, expires_at_epoch) VALUES (?,?,?,?)",
        %w[rl1 host 1 100]
      )

      compactor = described_class.new(db_registry: reg, blob_store: bs, retention_epochs: 50)
      r = compactor.compact(current_epoch: 1000)

      expect(r).to include(
        sagas_pruned: 1,
        transitions_pruned: 1,
        events_archived: 1,
        recovery_leases_purged: 1,
        intent_reservations_purged: 1,
        blobs_collected: 1
      )

      archive = File.join(reg.kernel_dir, "event_store_archive.db")
      adb = SQLite3::Database.new(archive, results_as_hash: true)
      archive_rows = adb.get_first_value("SELECT COUNT(*) FROM events").to_i
      adb.close

      expect(
        [
          rt.get_first_value("SELECT COUNT(*) FROM sagas WHERE manifest_id = ?", ["old-m"]).to_i,
          rt.get_first_value("SELECT COUNT(*) FROM sagas WHERE manifest_id = ?", ["act-m"]).to_i,
          es.get_first_value("SELECT COUNT(*) FROM events WHERE manifest_id = ?", ["act-m"]).to_i,
          File.exist?(bs.path_for_hex(keep_hex)),
          File.exist?(bs.path_for_hex(drop_hex)),
          archive_rows
        ]
      ).to eq([0, 1, 1, true, false, 1])
    end
  end
  # rubocop:enable RSpec/ExampleLength

  describe OllamaAgent::Runtime::CompactorRunner do
    it "runs the compactor once per interval epochs" do
      compactor = instance_double(OllamaAgent::Runtime::Compactor, compact: { sagas_pruned: 1 })
      runner = described_class.new(compactor: compactor, interval_epochs: 10)

      expect(runner.tick(current_epoch: 5)).to eq(sagas_pruned: 1)
      expect(runner.tick(current_epoch: 10)).to be_nil
      expect(runner.tick(current_epoch: 15)).to eq(sagas_pruned: 1)
    end
  end
end

# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength -- compaction orchestrates several durable stores in one unit
require "fileutils"
require "json"
require "sqlite3"

require_relative "event_store"

module OllamaAgent
  module Runtime
    # Prunes terminal kernel state, cold-archives old WAL events, and garbage-collects blob files.
    class Compactor
      EVENT_ARCHIVE_BASENAME = "event_store_archive.db"

      # Logical epoch extracted from +logical_stamp+ (+epoch:seq+).
      EVENT_EPOCH_SQL = "(CASE WHEN instr(logical_stamp, ':') > 0 THEN " \
                        "CAST(substr(logical_stamp, 1, instr(logical_stamp, ':') - 1) AS INTEGER) " \
                        "ELSE 0 END)"

      STANDALONE_EVENTS_DDL = <<~SQL
        CREATE TABLE IF NOT EXISTS events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          manifest_id TEXT NOT NULL,
          logical_stamp TEXT NOT NULL,
          kind TEXT NOT NULL,
          payload BLOB NOT NULL,
          intent_hash TEXT,
          created_at TEXT NOT NULL
        );
      SQL

      def initialize(db_registry:, blob_store:, retention_epochs: 100_000)
        @db_registry = db_registry
        @blob_store = blob_store
        @retention = retention_epochs.to_i
      end

      # @return [Hash] per-field prune/archive counts
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- single orchestration entry for operators
      def compact(current_epoch:)
        epoch = current_epoch.to_i
        cutoff = epoch - @retention
        ref_shas = Set.new
        sagas_pruned = 0
        transitions_pruned = 0
        recovery_leases_purged = 0
        intent_reservations_purged = 0

        @db_registry.runtime.transaction(:immediate) do
          ref_shas = referenced_blob_shas
          sagas_pruned, transitions_pruned = prune_terminal_sagas_and_transitions(cutoff)
          recovery_leases_purged = purge_recovery_leases(epoch)
          intent_reservations_purged = purge_intent_reservations(cutoff)
        end

        events_archived = archive_events(cutoff: cutoff)
        blobs_collected = prune_unreferenced_blobs(ref_shas)

        counts = {
          sagas_pruned: sagas_pruned,
          transitions_pruned: transitions_pruned,
          events_archived: events_archived,
          blobs_collected: blobs_collected,
          recovery_leases_purged: recovery_leases_purged,
          intent_reservations_purged: intent_reservations_purged
        }
        log_compaction(epoch, counts)
        counts
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private

      def runtime_db
        @db_registry.runtime
      end

      def event_db
        @db_registry.event_store
      end

      def archive_path
        File.join(@db_registry.kernel_dir, EVENT_ARCHIVE_BASENAME)
      end

      def referenced_blob_shas
        set = Set.new
        collect_compensation_shas(set)
        active = active_manifest_ids
        collect_mutation_blob_shas(active, set)
        set
      end

      def collect_compensation_shas(set)
        runtime_db.execute("SELECT DISTINCT pre_blob_sha AS s FROM compensations WHERE pre_blob_sha IS NOT NULL") do |r|
          sha = normalize_blob_sha(r["s"])
          set << sha if sha
        end
      end

      def active_manifest_ids
        runtime_db.execute("SELECT manifest_id FROM sagas WHERE terminal = 0").map { |row| row["manifest_id"] }
      end

      def collect_mutation_blob_shas(manifest_ids, set)
        return if manifest_ids.empty?

        manifest_ids.each_slice(80) do |batch|
          qmarks = batch.map { "?" }.join(",")
          sql = "SELECT payload FROM events WHERE kind = ? AND manifest_id IN (#{qmarks})"
          event_db.execute(sql, [EventStore::MUTATION_KIND] + batch) do |row|
            append_sha_from_mutation_payload(row["payload"], set)
          end
        end
      end

      def append_sha_from_mutation_payload(blob, set)
        h = JSON.parse(blob.to_s)
        return unless h["op"].to_s == "atomic_write"

        sha = h["sha256"].to_s.downcase.delete_prefix("sha256:")
        set << sha if sha.match?(/\A[0-9a-f]{64}\z/)
      rescue JSON::ParserError
        nil
      end

      def normalize_blob_sha(value)
        s = value.to_s.strip.downcase.delete_prefix("sha256:")
        return nil unless s.match?(/\A[0-9a-f]{64}\z/)

        s
      end

      # rubocop:disable Metrics/MethodLength -- explicit SQL batch for saga + transition tombstones
      def prune_terminal_sagas_and_transitions(cutoff)
        mids = runtime_db.execute(
          "SELECT manifest_id FROM sagas WHERE terminal = 1 AND last_transition_at_epoch < ?",
          [cutoff]
        ).map { |r| r["manifest_id"] }
        return [0, 0] if mids.empty?

        qmarks = mids.map { "?" }.join(",")
        trans = runtime_db.get_first_value(
          "SELECT COUNT(*) FROM saga_transitions WHERE manifest_id IN (#{qmarks})",
          mids
        ).to_i
        runtime_db.execute("DELETE FROM saga_transitions WHERE manifest_id IN (#{qmarks})", mids)
        runtime_db.execute("DELETE FROM sagas WHERE manifest_id IN (#{qmarks})", mids)
        [mids.size, trans]
      end
      # rubocop:enable Metrics/MethodLength

      def purge_recovery_leases(current_epoch)
        n = runtime_db.get_first_value(
          "SELECT COUNT(*) FROM recovery_leases WHERE expires_at_epoch < ?",
          [current_epoch]
        ).to_i
        runtime_db.execute("DELETE FROM recovery_leases WHERE expires_at_epoch < ?", [current_epoch])
        n
      end

      def purge_intent_reservations(cutoff)
        n = runtime_db.get_first_value(
          "SELECT COUNT(*) FROM intent_reservations WHERE created_at_epoch < ?",
          [cutoff]
        ).to_i
        runtime_db.execute("DELETE FROM intent_reservations WHERE created_at_epoch < ?", [cutoff])
        n
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- archive copy then delete must stay explicit
      def archive_events(cutoff:)
        path = File.expand_path(archive_path)
        FileUtils.mkdir_p(File.dirname(path))
        guard_sql, guard_binds = manifest_exclusion_sql(active_manifest_ids)
        where = "#{EVENT_EPOCH_SQL} < ?#{guard_sql}"
        select_binds = [cutoff] + guard_binds

        ids = event_db.execute("SELECT id FROM events WHERE #{where}", select_binds).map { |r| r["id"] }
        return 0 if ids.empty?

        qmarks = ids.map { "?" }.join(",")
        sel = "SELECT id, manifest_id, logical_stamp, kind, payload, intent_hash, created_at FROM events " \
              "WHERE id IN (#{qmarks})"
        rows = event_db.execute(sel, ids)

        SQLite3::Database.new(path) do |arc|
          arc.results_as_hash = true
          arc.busy_timeout = 60_000
          arc.execute_batch(STANDALONE_EVENTS_DDL)
          arc.transaction(:immediate) do
            rows.each do |r|
              arc.execute(
                "INSERT INTO events (id, manifest_id, logical_stamp, kind, payload, intent_hash, created_at) " \
                "VALUES (?,?,?,?,?,?,?)",
                [
                  r["id"],
                  r["manifest_id"],
                  r["logical_stamp"],
                  r["kind"],
                  r["payload"],
                  r["intent_hash"],
                  r["created_at"]
                ]
              )
            end
          end
        end

        event_db.transaction(:immediate) do
          event_db.execute("DELETE FROM events WHERE id IN (#{qmarks})", ids)
        end

        ids.size
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      def manifest_exclusion_sql(manifest_ids)
        return ["", []] if manifest_ids.empty?

        qmarks = manifest_ids.map { "?" }.join(",")
        [" AND manifest_id NOT IN (#{qmarks}) ", manifest_ids]
      end

      def prune_unreferenced_blobs(referenced)
        removed = 0
        @blob_store.each_stored_hex do |hex|
          next if referenced.include?(hex)

          FileUtils.rm_f(@blob_store.path_for_hex(hex))
          removed += 1
        end
        removed
      end

      def log_compaction(epoch, counts)
        OllamaAgent.logger.info(
          JSON.generate(
            event: "kernel.compactor",
            current_epoch: epoch,
            retention_epochs: @retention,
            **counts
          )
        )
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

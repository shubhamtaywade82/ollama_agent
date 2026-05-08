# frozen_string_literal: true

require "sqlite3"

module OllamaAgent
  module Runtime
    # Append-only event log in +event_store.db+.
    class EventStore
      MUTATION_KIND = "mutation"

      # @param db [SQLite3::Database]
      def initialize(db)
        @db = db
      end

      # Appends one event. +created_at+ must be a logical stamp (no wall clock); defaults to +logical_stamp+.
      # @return [:inserted, :duplicate] +:duplicate+ when +intent_hash+ violates uniqueness
      # rubocop:disable Metrics/ParameterLists -- explicit event fields
      def append(manifest_id:, logical_stamp:, kind:, payload:, intent_hash: nil, created_at: nil)
        stamp = created_at || logical_stamp
        blob = payload_to_blob(payload)
        insert_event_row([manifest_id, logical_stamp, kind, blob, intent_hash, stamp])
        :inserted
      rescue SQLite3::ConstraintException => e
        raise unless intent_hash && intent_hash_duplicate_constraint?(e)

        :duplicate
      end
      # rubocop:enable Metrics/ParameterLists

      # Yields each event row for +manifest_id+ in +id+ order (+results_as_hash+ keys are strings).
      def each_for(manifest_id:, &block)
        return to_enum(:each_for, manifest_id: manifest_id) unless block

        @db.execute(
          "SELECT id, manifest_id, logical_stamp, kind, payload, intent_hash, created_at " \
          "FROM events WHERE manifest_id = ? ORDER BY id ASC",
          [manifest_id],
          &block
        )
      end

      # All mutation events in global +id+ order (workspace-level WAL replay).
      def each_mutation_globally(&block)
        return to_enum(:each_mutation_globally) unless block

        @db.execute(
          "SELECT id, manifest_id, logical_stamp, kind, payload, intent_hash, created_at " \
          "FROM events WHERE kind = ? ORDER BY id ASC",
          [MUTATION_KIND],
          &block
        )
      end

      private

      def insert_event_row(values)
        @db.execute(
          "INSERT INTO events (manifest_id, logical_stamp, kind, payload, intent_hash, created_at) " \
          "VALUES (?,?,?,?,?,?)",
          values
        )
      end

      # sqlite3-ruby raises ConstraintException with #code 19 (SQLITE_CONSTRAINT) for UNIQUE failures;
      # message is usually "UNIQUE constraint failed: events.intent_hash" (column), not the index name.
      def intent_hash_duplicate_constraint?(error)
        msg = error.message.to_s
        return true if msg.include?("idx_events_intent_hash_unique")

        error.respond_to?(:code) && error.code == 19 && msg.include?("intent_hash")
      end

      # Binds as SQL BLOB (plain String would be TEXT in sqlite3-ruby).
      def payload_to_blob(payload)
        SQLite3::Blob.new(payload.to_s.b)
      end
    end
  end
end

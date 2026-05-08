# frozen_string_literal: true

require "sqlite3"

module OllamaAgent
  module Runtime
    # Durable integration work queue in +runtime.db+.
    class IntegrationQueue
      STATUS_PENDING = "pending"
      STATUS_CLAIMED = "claimed"
      STATUS_DONE = "done"

      # @param db [SQLite3::Database]
      def initialize(db)
        @db = db
      end

      # @param created_at [String] logical stamp (no wall clock)
      def enqueue(manifest_id:, payload:, created_at:)
        blob = payload.is_a?(String) ? payload : payload.to_s
        @db.execute(
          "INSERT INTO integration_queue (manifest_id, payload, status, created_at) VALUES (?,?,?,?)",
          [manifest_id, blob, STATUS_PENDING, created_at]
        )
      end

      # @return [Hash, nil] next pending row as hash, or nil; row is marked +claimed+
      def claim_next
        @db.transaction(:immediate) do
          id = next_pending_id
          id ? claim_row_by_id(id) : nil
        end
      end

      # Marks a claimed row +done+.
      def mark_done(id:)
        @db.execute(
          "UPDATE integration_queue SET status = ? WHERE id = ?",
          [STATUS_DONE, id]
        )
      end

      private

      def next_pending_id
        @db.get_first_value(
          "SELECT id FROM integration_queue WHERE status = ? ORDER BY id LIMIT 1",
          [STATUS_PENDING]
        )
      end

      def claim_row_by_id(id)
        @db.execute(
          "UPDATE integration_queue SET status = ? WHERE id = ?",
          [STATUS_CLAIMED, id]
        )
        @db.get_first_row("SELECT * FROM integration_queue WHERE id = ?", [id])
      end
    end
  end
end

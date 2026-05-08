# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # SQLite-backed ledger of per-path compensation steps for a saga +manifest_id+.
    class CompensationManifest
      INSERT_COMPENSATION_SQL = "INSERT INTO compensations " \
                                "(manifest_id, path, op, pre_blob_sha, pre_existed, fencing_token, " \
                                "logical_stamp, applied) VALUES (?,?,?,?,?,?,?,0)"

      def initialize(db)
        @db = db
      end

      # rubocop:disable Metrics/ParameterLists, Naming/MethodParameterName -- +op+ matches DB column
      def record(manifest_id:, path:, op:, pre_blob_sha:, pre_existed:, fencing_token:, logical_stamp:)
        insert_compensation_row(
          manifest_id: manifest_id,
          path: path,
          operation: op,
          pre_blob_sha: pre_blob_sha,
          pre_existed: pre_existed,
          fencing_token: fencing_token,
          logical_stamp: logical_stamp
        )
      end
      # rubocop:enable Metrics/ParameterLists, Naming/MethodParameterName

      def each_unapplied(manifest_id:, &block)
        return enum_for(:each_unapplied, manifest_id: manifest_id) unless block

        sql = "SELECT * FROM compensations WHERE manifest_id = ? AND applied = 0 ORDER BY id DESC"
        @db.execute(sql, [manifest_id], &block)
      end

      def mark_applied(id:)
        @db.transaction(:immediate) do
          @db.execute("UPDATE compensations SET applied = 1 WHERE id = ?", [id.to_i])
        end
      end

      private

      def insert_compensation_row(row)
        mid = nil
        @db.transaction(:immediate) do
          @db.execute(INSERT_COMPENSATION_SQL, compensation_bind_values(row))
          mid = @db.last_insert_row_id
        end
        mid
      end

      def compensation_bind_values(row)
        [
          row.fetch(:manifest_id),
          row.fetch(:path),
          row.fetch(:operation),
          row.fetch(:pre_blob_sha),
          row.fetch(:pre_existed).to_i,
          row.fetch(:fencing_token).to_i,
          row.fetch(:logical_stamp).to_s
        ]
      end
    end
  end
end

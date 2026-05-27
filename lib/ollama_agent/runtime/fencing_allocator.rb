# frozen_string_literal: true

require "sqlite3"

module OllamaAgent
  module Runtime
    # Monotonic fencing integers per +scope+ in +runtime.db+ (UPSERT increment).
    class FencingAllocator
      UPSERT_SQL = "INSERT INTO fencing_tokens (scope, last_token) VALUES (?, 1) " \
                   "ON CONFLICT(scope) DO UPDATE SET last_token = last_token + 1"

      # @param db [SQLite3::Database]
      def initialize(db)
        @db = db
      end

      # @return [Integer] new token for +scope+
      def allocate(scope:)
        @db.transaction(:immediate) { allocate_joining(scope: scope) }
      end

      # Like {#allocate} but assumes the caller already holds an open +transaction(:immediate)+ on +@db+.
      # @return [Integer]
      def allocate_joining(scope:)
        @db.execute(UPSERT_SQL, [scope])
        @db.get_first_value("SELECT last_token FROM fencing_tokens WHERE scope = ?", [scope]).to_i
      end
    end
  end
end

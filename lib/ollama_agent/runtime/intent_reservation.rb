# frozen_string_literal: true

require "json"

module OllamaAgent
  module Runtime
    # Tracks intent hashes against sorted JSON scope lists for pre-flight conflict detection.
    class IntentReservation
      def initialize(db)
        @db = db
      end

      # @return [:reserved, :duplicate, :conflict]
      def reserve(intent_hash:, manifest_id:, scopes:, current_epoch:)
        outcome = :reserved
        @db.transaction(:immediate) do
          outcome = reserve_joining(
            intent_hash: intent_hash,
            manifest_id: manifest_id,
            scopes: scopes,
            current_epoch: current_epoch
          )
        end
        outcome
      end

      # Like {#reserve} but assumes the caller already holds +transaction(:immediate)+ on +@db+.
      # @return [:reserved, :duplicate, :conflict]
      def reserve_joining(intent_hash:, manifest_id:, scopes:, current_epoch:)
        normalized = normalize_scopes(scopes)
        reserve_transaction(intent_hash, manifest_id, normalized, current_epoch)
      end

      # @return [:ok, :missing, :wrong_owner]
      def release(intent_hash:, manifest_id:)
        outcome = :ok
        @db.transaction(:immediate) do
          outcome = release_joining(intent_hash: intent_hash, manifest_id: manifest_id)
        end
        outcome
      end

      # Like {#release} but assumes the caller already holds +transaction(:immediate)+ on +@db+.
      # @return [:ok, :missing, :wrong_owner]
      def release_joining(intent_hash:, manifest_id:)
        release_transaction(intent_hash, manifest_id)
      end

      # @return [Array<String>] intent_hash values whose scopes intersect +scopes+
      def conflicts_for(scopes:)
        wanted = normalize_scopes(scopes)
        found = []
        @db.execute("SELECT intent_hash, scopes FROM intent_reservations") do |row|
          other = JSON.parse(row["scopes"])
          found << row["intent_hash"] if scopes_overlap?(wanted, other)
        end
        found
      end

      private

      def reserve_transaction(intent_hash, manifest_id, normalized, current_epoch)
        return :duplicate if reservation_for_intent?(intent_hash)
        return :conflict if conflicting_scopes?(normalized)

        insert_reservation!(intent_hash, manifest_id, normalized, current_epoch)
        :reserved
      end

      def insert_reservation!(intent_hash, manifest_id, normalized, current_epoch)
        payload = JSON.generate(normalized)
        @db.execute(
          "INSERT INTO intent_reservations (intent_hash, manifest_id, scopes, created_at_epoch) " \
          "VALUES (?,?,?,?)",
          [intent_hash, manifest_id, payload, current_epoch.to_i]
        )
      end

      def release_transaction(intent_hash, manifest_id)
        row = @db.get_first_row(
          "SELECT manifest_id FROM intent_reservations WHERE intent_hash = ?",
          [intent_hash]
        )
        return :missing unless row
        return :wrong_owner if row["manifest_id"] != manifest_id

        @db.execute("DELETE FROM intent_reservations WHERE intent_hash = ?", [intent_hash])
        :ok
      end

      def normalize_scopes(scopes)
        scopes.map(&:to_s).uniq.sort
      end

      def reservation_for_intent?(intent_hash)
        @db.get_first_value(
          "SELECT 1 FROM intent_reservations WHERE intent_hash = ? LIMIT 1",
          [intent_hash]
        )
      end

      def conflicting_scopes?(normalized)
        @db.execute("SELECT scopes FROM intent_reservations") do |row|
          other = JSON.parse(row["scopes"])
          return true if scopes_overlap?(normalized, other)
        end
        false
      end

      def scopes_overlap?(left, right)
        left.intersect?(right)
      end
    end
  end
end

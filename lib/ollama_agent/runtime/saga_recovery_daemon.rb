# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # Exclusive per-manifest recovery lease + compensation + saga seal.
    class SagaRecoveryDaemon
      def initialize(db:, saga_coordinator:, compensation_engine:, clock_epoch_provider:)
        @db = db
        @saga_coordinator = saga_coordinator
        @compensation_engine = compensation_engine
        @clock_epoch_provider = clock_epoch_provider
      end

      # @param holder [String] logical worker id
      # @param ttl_epochs [Integer] lease length in logical epochs (caller-owned clock).
      # @return [Array<Hash>] each element +:manifest_id+, +:status+
      def recover_orphans(holder:, ttl_epochs: 60)
        epoch = @clock_epoch_provider.call.to_i
        ttl = ttl_epochs.to_i
        outcomes = []
        @saga_coordinator.each_active do |saga|
          outcomes << recover_one(saga[:manifest_id], holder, epoch, ttl)
        end
        outcomes
      end

      private

      def recover_one(manifest_id, holder, epoch, ttl)
        claim = :skipped
        @db.transaction(:immediate) do
          claim = write_recovery_lease_claim(manifest_id, holder, epoch, ttl)
        end
        return { manifest_id: manifest_id, status: :lease_held_by_other } if claim == :skipped

        @compensation_engine.compensate(manifest_id: manifest_id, logical_stamp: epoch.to_s)
        saga_out = @saga_coordinator.compensate(manifest_id: manifest_id, reason: "recovery")
        release_lease(manifest_id) if saga_terminal_outcome?(saga_out)

        status = saga_terminal_outcome?(saga_out) ? :recovered : :saga_compensate_failed
        { manifest_id: manifest_id, status: status }
      end

      def saga_terminal_outcome?(saga_out)
        %i[ok sealed].include?(saga_out)
      end

      # @return [:claimed, :skipped] :skipped when another holder holds a non-expired lease
      def write_recovery_lease_claim(manifest_id, holder, epoch, ttl)
        row = @db.get_first_row("SELECT * FROM recovery_leases WHERE manifest_id = ?", [manifest_id])
        return :skipped if lease_held_by_other?(row, holder, epoch)

        upsert_recovery_lease(row, manifest_id, holder, epoch, ttl)
        :claimed
      end

      def lease_held_by_other?(row, holder, epoch)
        row && row["expires_at_epoch"].to_i > epoch && row["holder"] != holder
      end

      def upsert_recovery_lease(row, manifest_id, holder, epoch, ttl)
        expires_at = epoch + ttl
        return update_recovery_lease_row(manifest_id, holder, epoch, expires_at) if row

        insert_recovery_lease_row(manifest_id, holder, epoch, expires_at)
      end

      def update_recovery_lease_row(manifest_id, holder, epoch, expires_at)
        @db.execute(
          "UPDATE recovery_leases SET holder = ?, acquired_at_epoch = ?, expires_at_epoch = ? " \
          "WHERE manifest_id = ?",
          [holder, epoch, expires_at, manifest_id]
        )
      end

      def insert_recovery_lease_row(manifest_id, holder, epoch, expires_at)
        @db.execute(
          "INSERT INTO recovery_leases (manifest_id, holder, acquired_at_epoch, expires_at_epoch) " \
          "VALUES (?,?,?,?)",
          [manifest_id, holder, epoch, expires_at]
        )
      end

      def release_lease(manifest_id)
        @db.transaction(:immediate) do
          @db.execute("DELETE FROM recovery_leases WHERE manifest_id = ?", [manifest_id])
        end
      end
    end
  end
end

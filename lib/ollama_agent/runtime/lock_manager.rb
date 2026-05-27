# frozen_string_literal: true

require "securerandom"

module OllamaAgent
  module Runtime
    # Exclusive leases in +runtime.db+ keyed by +scope+ (caller-chosen string, often a path).
    #
    # Callers that acquire multiple scopes must do so in a consistent **lexicographic sort order**
    # across the codebase to avoid deadlocks; this class does not reorder scopes for you.
    # rubocop:disable Metrics/ClassLength -- kernel lease + fencing in one cohesive unit
    class LockManager
      UPSERT_LOCK_SQL = "INSERT INTO locks " \
                        "(scope, lease_token, holder, acquired_at, expires_at_epoch, fencing_token) " \
                        "VALUES (?,?,?,?,?,?) " \
                        "ON CONFLICT(scope) DO UPDATE SET " \
                        "lease_token = excluded.lease_token, holder = excluded.holder, " \
                        "acquired_at = excluded.acquired_at, expires_at_epoch = excluded.expires_at_epoch, " \
                        "fencing_token = excluded.fencing_token"

      attr_reader :clock_epoch

      # @param db [SQLite3::Database]
      # @param fencing_allocator [FencingAllocator]
      # @param clock_epoch [Integer] initial logical epoch watermark (callers still pass +current_epoch:+ per call)
      def initialize(db:, fencing_allocator:, clock_epoch:)
        @db = db
        @fencing_allocator = fencing_allocator
        @clock_epoch = clock_epoch
      end

      # @return [Hash{:lease_token=>Integer, :fencing_token=>Integer}, :held, :stale_lease]
      def acquire(scope:, holder:, ttl_epochs:, current_epoch:)
        return :stale_lease if ttl_epochs.to_i < 1

        outcome = nil
        @db.transaction(:immediate) do
          outcome = resolve_acquire(scope, holder, ttl_epochs, current_epoch)
        end
        outcome
      end

      # @return [:ok, :stale_lease, :expired]
      def renew(scope:, holder:, lease_token:, ttl_epochs:, current_epoch:)
        return :stale_lease if ttl_epochs.to_i < 1

        outcome = :ok
        @db.transaction(:immediate) do
          outcome = resolve_renew(scope, holder, lease_token, ttl_epochs, current_epoch)
        end
        outcome
      end

      # @return [:ok, :stale_lease]
      def release(scope:, holder:, lease_token:)
        outcome = :ok
        @db.transaction(:immediate) do
          outcome = resolve_release(scope, holder, lease_token)
        end
        outcome
      end

      # @return [Integer] rows deleted
      def prune_expired(current_epoch:)
        @db.transaction(:immediate) do
          @db.execute("DELETE FROM locks WHERE expires_at_epoch <= ?", [current_epoch.to_i])
          @db.changes
        end
      end

      private

      def resolve_acquire(scope, holder, ttl_epochs, current_epoch)
        row = fetch_lock_row(scope)
        if active_lock_held_by_other?(row, holder, current_epoch)
          :held
        elsif active_lock_reentrant?(row, holder, current_epoch)
          reentrant_lock_tokens(row)
        else
          insert_or_replace_lock!(scope, holder, ttl_epochs, current_epoch)
        end
      end

      def resolve_renew(scope, holder, lease_token, ttl_epochs, current_epoch)
        row = fetch_lock_row(scope)
        return :stale_lease unless row
        return :expired if row["expires_at_epoch"].to_i <= current_epoch.to_i
        return :stale_lease unless renewal_token_matches?(row, holder, lease_token)

        bump_expiry!(scope, current_epoch, ttl_epochs)
        :ok
      end

      def renewal_token_matches?(row, holder, lease_token)
        row["holder"] == holder && row["lease_token"].to_i == lease_token.to_i
      end

      def bump_expiry!(scope, current_epoch, ttl_epochs)
        new_expires = current_epoch.to_i + ttl_epochs.to_i
        @db.execute(
          "UPDATE locks SET expires_at_epoch = ? WHERE scope = ?",
          [new_expires, scope]
        )
      end

      def resolve_release(scope, holder, lease_token)
        row = fetch_lock_row(scope)
        return :stale_lease unless row
        return :stale_lease unless renewal_token_matches?(row, holder, lease_token)

        @db.execute("DELETE FROM locks WHERE scope = ?", [scope])
        :ok
      end

      def fetch_lock_row(scope)
        @db.get_first_row("SELECT * FROM locks WHERE scope = ?", [scope])
      end

      def active_lock_held_by_other?(row, holder, current_epoch)
        row &&
          row["expires_at_epoch"].to_i > current_epoch.to_i &&
          row["holder"] != holder
      end

      def active_lock_reentrant?(row, holder, current_epoch)
        row &&
          row["expires_at_epoch"].to_i > current_epoch.to_i &&
          row["holder"] == holder
      end

      def reentrant_lock_tokens(row)
        {
          lease_token: row["lease_token"].to_i,
          fencing_token: row["fencing_token"].to_i
        }
      end

      def insert_or_replace_lock!(scope, holder, ttl_epochs, current_epoch)
        lease_token = random_lease_token
        fencing_token = @fencing_allocator.allocate_joining(scope: scope)
        expires_at = current_epoch.to_i + ttl_epochs.to_i
        acquired_at = current_epoch.to_s
        @db.execute(UPSERT_LOCK_SQL, [scope, lease_token, holder, acquired_at, expires_at, fencing_token])
        { lease_token: lease_token, fencing_token: fencing_token }
      end

      def random_lease_token
        SecureRandom.random_number(1..((1 << 62) - 1))
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

# frozen_string_literal: true

require_relative "file_atomic_swap"

module OllamaAgent
  module Runtime
    # Replays recorded compensations (blob restore or unlink) for a +manifest_id+.
    class CompensationEngine
      def initialize(blob_store:, compensation_manifest:, atomic_mutator:, fencing_allocator:)
        @blob_store = blob_store
        @compensation_manifest = compensation_manifest
        @atomic_mutator = atomic_mutator
        @fencing_allocator = fencing_allocator
      end

      # @return [Hash] +:restored+, +:missing+, +:errors+ (Array of error hashes)
      def compensate(manifest_id:, logical_stamp:)
        raise ArgumentError, "kernel wiring incomplete" unless coordinator_wired?

        tallies = { restored: 0, missing: 0 }
        errors = []
        @compensation_manifest.each_unapplied(manifest_id: manifest_id) do |row|
          apply_one(row, tallies, errors, logical_stamp)
        end
        { restored: tallies[:restored], missing: tallies[:missing], errors: errors }
      end

      private

      attr_reader :blob_store, :compensation_manifest, :atomic_mutator, :fencing_allocator

      def coordinator_wired?
        !atomic_mutator.nil? && !fencing_allocator.nil?
      end

      def apply_one(row, tallies, errors, logical_stamp)
        row_id = row["id"].to_i
        if row["pre_existed"].to_i.zero?
          apply_unlink(row, row_id, tallies, errors, logical_stamp)
        else
          apply_restore(row, row_id, tallies, errors, logical_stamp)
        end
      end

      def apply_unlink(row, row_id, tallies, errors, logical_stamp)
        path = row["path"].to_s
        unlink_target(path)
        compensation_manifest.mark_applied(id: row_id)
        tallies[:missing] += 1
      rescue StandardError => e
        errors << error_payload(row_id, e, logical_stamp)
      end

      def apply_restore(row, row_id, tallies, errors, logical_stamp)
        path = row["path"].to_s
        sha = row["pre_blob_sha"].to_s
        raise ArgumentError, "pre_blob_sha required for restore" if sha.empty?

        bytes = blob_store.get(sha256: sha)
        FileAtomicSwap.write_bytes!(path, bytes)
        compensation_manifest.mark_applied(id: row_id)
        tallies[:restored] += 1
      rescue StandardError => e
        errors << error_payload(row_id, e, logical_stamp)
      end

      def unlink_target(path)
        return unless File.exist?(path)

        raise Errno::EISDIR, path if File.directory?(path)

        File.unlink(path)
      end

      def error_payload(row_id, exception, logical_stamp)
        {
          id: row_id,
          error_class: exception.class.name,
          message: exception.message,
          logical_stamp: logical_stamp.to_s
        }
      end
    end
  end
end

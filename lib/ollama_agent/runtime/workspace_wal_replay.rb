# frozen_string_literal: true

require "fileutils"
require "json"
require "sqlite3"

require_relative "blob_store"
require_relative "event_store"
require_relative "file_atomic_swap"

module OllamaAgent
  module Runtime
    # Replays global mutation WAL (+event_store.db+) onto a workspace tree using blob content-addresses.
    class WorkspaceWalReplay
      def initialize(workspace_root:, event_store_db_path:, blob_store_kernel_dir:)
        @root = File.expand_path(workspace_root.to_s)
        @event_store_db_path = event_store_db_path.to_s
        @blob_store = BlobStore.new(kernel_dir: blob_store_kernel_dir)
      end

      def replay!
        db = SQLite3::Database.new(@event_store_db_path, results_as_hash: true)
        store = EventStore.new(db)
        store.each_mutation_globally do |row|
          apply_mutation_payload(row["payload"])
        end
      ensure
        db&.close
      end

      private

      def apply_mutation_payload(blob)
        h = JSON.parse(blob.to_s)
        case h["op"]
        when "atomic_write"
          apply_atomic_write(h)
        when "delete_file"
          apply_delete(h)
        when "rename_file"
          apply_rename(h)
        end
      end

      def apply_atomic_write(h)
        path = h.fetch("path").to_s
        sha = h["sha256"].to_s
        raise ArgumentError, "atomic_write replay requires sha256" if sha.empty?

        bytes = @blob_store.get(sha256: sha)
        absolute = File.expand_path(path, @root)
        FileUtils.mkdir_p(File.dirname(absolute))
        FileAtomicSwap.write_bytes!(absolute, bytes)
      end

      def apply_delete(h)
        path = h.fetch("path").to_s
        absolute = File.expand_path(path, @root)
        File.unlink(absolute) if File.file?(absolute)
      end

      def apply_rename(h)
        from = h.fetch("from").to_s
        to = h.fetch("to").to_s
        from_abs = File.expand_path(from, @root)
        to_abs = File.expand_path(to, @root)
        FileUtils.mkdir_p(File.dirname(to_abs))
        File.rename(from_abs, to_abs)
      end
    end
  end
end

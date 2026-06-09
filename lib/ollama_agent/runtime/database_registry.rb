# frozen_string_literal: true

require "sqlite3"
require "fileutils"

require_relative "schema_migrator"

module OllamaAgent
  module Runtime
    # Opens kernel SQLite databases under +root_dir+/.ollama_agent/kernel/ and applies idempotent migrations.
    class DatabaseRegistry
      # @param root_dir [String] workspace root
      def initialize(root_dir:)
        @root_dir = root_dir
        @kernel_dir = File.join(root_dir, ".ollama_agent", "kernel")
        @open_mutex = Mutex.new
        @event_store = nil
        @runtime = nil
        @migrations_ran = false
      end

      # @return [SQLite3::Database] event store connection (WAL, synchronous FULL)
      def event_store
        open_mutex_sync { @event_store ||= connect_event_store }
      end

      # @return [SQLite3::Database] runtime connection (WAL, synchronous NORMAL)
      def runtime
        open_mutex_sync { @runtime ||= connect_runtime }
      end

      attr_reader :kernel_dir

      private

      def open_mutex_sync(&)
        @open_mutex.synchronize(&)
      end

      def connect_event_store
        FileUtils.mkdir_p(@kernel_dir)
        run_kernel_migrations!
        open_connection(File.join(@kernel_dir, "event_store.db"), :event_store)
      end

      def connect_runtime
        FileUtils.mkdir_p(@kernel_dir)
        run_kernel_migrations!
        open_connection(File.join(@kernel_dir, "runtime.db"), :runtime)
      end

      def run_kernel_migrations!
        return if @migrations_ran

        SchemaMigrator.new(db_registry: self).migrate!
        @migrations_ran = true
      end

      def open_connection(path, role)
        db = SQLite3::Database.new(path)
        db.results_as_hash = true
        db.busy_timeout = 60_000
        apply_pragmas!(db, role)
        db
      end

      def apply_pragmas!(db, role)
        db.execute("PRAGMA journal_mode=WAL")
        sync = role == :event_store ? "FULL" : "NORMAL"
        db.execute("PRAGMA synchronous=#{sync}")
      end
    end
  end
end

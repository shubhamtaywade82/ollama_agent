# frozen_string_literal: true

require "sqlite3"
require "fileutils"

module OllamaAgent
  module Runtime
    # Opens kernel SQLite databases under +root_dir+/.ollama_agent/kernel/ and applies idempotent schema.
    class DatabaseRegistry
      SCHEMA_LINE = /^-- ### (\S+)\s*$/

      class << self
        # @return [Array(String, String)] SQL bodies for event_store.db and runtime.db
        def schema_sections
          @schema_sections ||= load_schema_sections
        end

        private

        def load_schema_sections
          path = File.join(OllamaAgent.gem_root, "db", "ollama_agent", "schema.sql")
          split_schema(File.read(path))
        end

        # rubocop:disable Metrics/MethodLength -- line-oriented section parser
        def split_schema(contents)
          sections = {}
          current = nil
          buffer = +""

          contents.each_line do |line|
            if (m = line.match(SCHEMA_LINE))
              sections[current] = buffer.strip if current
              buffer = +""
              current = m[1]
            else
              buffer << line
            end
          end
          sections[current] = buffer.strip if current

          [sections.fetch("event_store.db"), sections.fetch("runtime.db")]
        end
        # rubocop:enable Metrics/MethodLength
      end

      # @param root_dir [String] workspace root
      def initialize(root_dir:)
        @root_dir = root_dir
        @kernel_dir = File.join(root_dir, ".ollama_agent", "kernel")
        @open_mutex = Mutex.new
        @event_store = nil
        @runtime = nil
      end

      # @return [SQLite3::Database] event store connection (WAL, synchronous FULL)
      def event_store
        open_mutex_sync { @event_store ||= connect_event_store }
      end

      # @return [SQLite3::Database] runtime connection (WAL, synchronous NORMAL)
      def runtime
        open_mutex_sync { @runtime ||= connect_runtime }
      end

      private

      def open_mutex_sync(&)
        @open_mutex.synchronize(&)
      end

      def connect_event_store
        FileUtils.mkdir_p(@kernel_dir)
        sql, = self.class.schema_sections
        open_db(File.join(@kernel_dir, "event_store.db"), sql)
      end

      def connect_runtime
        FileUtils.mkdir_p(@kernel_dir)
        _, sql = self.class.schema_sections
        open_db(File.join(@kernel_dir, "runtime.db"), sql)
      end

      def open_db(path, schema_sql)
        db = SQLite3::Database.new(path)
        db.results_as_hash = true
        db.execute_batch(schema_sql)
        db
      end
    end
  end
end

# frozen_string_literal: true

require "sqlite3"
require "fileutils"

module OllamaAgent
  module Runtime
    # Applies versioned SQL migrations under +db/ollama_agent/migrations/+ to kernel SQLite files.
    class SchemaMigrator
      SCHEMA_LINE = /^-- ### (\S+)\s*$/

      class << self
        def migrations_dir
          File.join(OllamaAgent.gem_root, "db", "ollama_agent", "migrations")
        end

        def migration_files
          return [] unless File.directory?(migrations_dir)

          Dir.children(migrations_dir).grep(/\.sql\z/).sort_by do |name|
            Integer(name[/\A(\d+)_/, 1])
          end
        end

        def migration_versions
          migration_files.map { |f| Integer(f[/\A(\d+)_/, 1]) }
        end

        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- line-oriented section parser
        def split_for_role(contents, role)
          wanted = role == :event_store ? "event_store.db" : "runtime.db"
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

          sections.fetch(wanted, "").to_s.strip
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      end

      def initialize(db_registry:)
        @db_registry = db_registry
      end

      # @return [Integer] highest migration version present on disk (0 when none)
      def current_version
        self.class.migration_versions.max || 0
      end

      # @return [Array<Integer>] newly applied migration version numbers (unique, sorted)
      def migrate!
        FileUtils.mkdir_p(@db_registry.kernel_dir)
        applied = []
        event_path = File.join(@db_registry.kernel_dir, "event_store.db")
        runtime_path = File.join(@db_registry.kernel_dir, "runtime.db")
        migrate_one_database!(event_path, :event_store, applied)
        migrate_one_database!(runtime_path, :runtime, applied)
        applied.uniq.sort
      end

      # @return [Integer] highest recorded version for an on-disk database file
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength -- defensive SQLite open
      def self.max_applied_version(path)
        return 0 unless File.file?(path)

        db = SQLite3::Database.new(path)
        db.results_as_hash = true
        return 0 unless migrations_table?(db)

        row = db.get_first_row("SELECT MAX(version) AS v FROM schema_migrations")
        v = row && (row["v"] || row[:v])
        Integer(v || 0)
      rescue SQLite3::Exception
        0
      ensure
        db&.close
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength

      def self.migrations_table?(db)
        !db.get_first_row(
          "SELECT 1 AS ok FROM sqlite_master WHERE type = 'table' AND name = ?",
          ["schema_migrations"]
        ).nil?
      end
      private_class_method :migrations_table?

      private

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one migration step per DB file
      def migrate_one_database!(path, role, applied_accum)
        db = SQLite3::Database.new(path)
        db.results_as_hash = true
        db.busy_timeout = 60_000
        ensure_schema_migrations_table!(db)

        self.class.migration_files.each do |filename|
          version = Integer(filename[/\A(\d+)_/, 1])
          next if migration_applied?(db, version)

          body = File.read(File.join(self.class.migrations_dir, filename))
          sql = self.class.split_for_role(body, role)
          db.transaction do
            db.execute_batch(sql) unless sql.empty?
            db.execute("INSERT INTO schema_migrations (version) VALUES (?)", [version])
          end
          applied_accum << version
        end
      ensure
        db&.close
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      def ensure_schema_migrations_table!(db)
        db.execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY NOT NULL
          );
        SQL
      end

      def migration_applied?(db, version)
        !db.get_first_row("SELECT 1 AS ok FROM schema_migrations WHERE version = ? LIMIT 1", version).nil?
      end
    end
  end
end

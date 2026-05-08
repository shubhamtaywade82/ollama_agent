# frozen_string_literal: true

require "fileutils"

require_relative "schema_migrator"

module OllamaAgent
  module Runtime
    # Readiness checks for kernel databases, blob storage, optional rollback signals, and schema drift.
    class KernelHealth
      def initialize(db_registry:, blob_store:, rollback_signals: nil)
        @registry = db_registry
        @blob_store = blob_store
        @rollback_signals = rollback_signals
      end

      # @return [Hash] +:status+ (:ok | :degraded | :unhealthy), +:checks+ (Hash)
      def check
        checks = {}
        checks[:event_store] = check_sqlite_writable(@registry.event_store)
        checks[:runtime] = check_sqlite_writable(@registry.runtime)
        checks[:blob_store] = check_blob_store_writable
        checks[:rollback_signals] = check_rollback_signals if @rollback_signals
        checks[:schema_migrations] = check_schema_versions
        { status: overall_status(checks), checks: checks }
      end

      private

      def check_sqlite_writable(db)
        db.execute("SELECT 1 AS ok")
        tmp = "health_probe_#{Process.pid}"
        db.execute("CREATE TEMP TABLE IF NOT EXISTS #{tmp} (x INTEGER)")
        db.execute("INSERT INTO #{tmp} VALUES (1)")
        { ok: true, detail: "writable" }
      rescue StandardError => e
        { ok: false, detail: "#{e.class}: #{e.message}" }
      end

      def check_blob_store_writable
        dir = @blob_store.blobs_root
        FileUtils.mkdir_p(dir)
        path = File.join(dir, ".health_probe_#{Process.pid}")
        File.binwrite(path, "ok")
        File.delete(path)
        { ok: true, detail: "writable" }
      rescue StandardError => e
        { ok: false, detail: "#{e.class}: #{e.message}" }
      end

      def check_rollback_signals
        snap = @rollback_signals.should_rollback?
        trigger = snap[:trigger] || snap["trigger"]
        { ok: !trigger, detail: trigger ? (snap[:reasons] || snap["reasons"]) : "clear" }
      end

      # rubocop:disable Metrics/MethodLength -- small version matrix for operators
      def check_schema_versions
        migrator = SchemaMigrator.new(db_registry: @registry)
        expected = migrator.current_version
        event_path = File.join(@registry.kernel_dir, "event_store.db")
        runtime_path = File.join(@registry.kernel_dir, "runtime.db")
        event_v = SchemaMigrator.max_applied_version(event_path)
        runtime_v = SchemaMigrator.max_applied_version(runtime_path)
        aligned = expected.positive? && event_v == expected && runtime_v == expected
        {
          ok: aligned,
          detail: {
            expected_version: expected,
            event_store_version: event_v,
            runtime_version: runtime_v
          }
        }
      end
      # rubocop:enable Metrics/MethodLength

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
      def overall_status(checks)
        return :unhealthy unless truthy?(checks[:event_store]&.[](:ok))
        return :unhealthy unless truthy?(checks[:runtime]&.[](:ok))
        return :unhealthy unless truthy?(checks[:blob_store]&.[](:ok))

        degraded = !truthy?(checks[:schema_migrations]&.[](:ok))
        degraded ||= checks[:rollback_signals] && !truthy?(checks[:rollback_signals][:ok])
        return :degraded if degraded

        :ok
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize

      def truthy?(value)
        value ? true : false
      end
    end
  end
end

# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # Persists per-manifest LLM cost rows in +runtime.db+.
    class CostLedger
      def initialize(db_registry:)
        @db_registry = db_registry
      end

      # @return [void]
      # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength -- explicit ledger columns
      def record(manifest_id:, model:, input_tokens:, output_tokens:, cost_usd:, current_epoch:)
        sql = "INSERT INTO cost_ledger (manifest_id, model, input_tokens, output_tokens, " \
              "cost_usd, created_at_epoch) VALUES (?, ?, ?, ?, ?, ?)"
        binds = [
          manifest_id,
          model.to_s,
          Integer(input_tokens),
          Integer(output_tokens),
          cost_usd.to_f,
          Integer(current_epoch)
        ]
        @db_registry.runtime.execute(sql, binds)
      end
      # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength

      # @return [Float]
      def total_for_manifest(manifest_id:)
        sql = "SELECT COALESCE(SUM(cost_usd), 0.0) AS t FROM cost_ledger WHERE manifest_id = ?"
        row = @db_registry.runtime.get_first_row(sql, manifest_id)
        extract_float(row, "t")
      end

      # @return [Float]
      def total_in_window(since_epoch:, until_epoch:)
        sql = "SELECT COALESCE(SUM(cost_usd), 0.0) AS t FROM cost_ledger " \
              "WHERE created_at_epoch >= ? AND created_at_epoch <= ?"
        row = @db_registry.runtime.get_first_row(sql, [Integer(since_epoch), Integer(until_epoch)])
        extract_float(row, "t")
      end

      private

      def extract_float(row, key)
        return 0.0 if row.nil?

        v = row[key] || row[key.to_sym]
        v.nil? ? 0.0 : v.to_f
      end
    end
  end
end

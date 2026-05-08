# frozen_string_literal: true

module OllamaAgent
  module Topology
    # In-memory multi-origin symbol storage (SQLite in E11b).
    class SymbolGraph
      def initialize
        @origins = {}
      end

      # rubocop:disable Naming/PredicateMethod -- API name; returns whether a new origin was stored.
      def add_origin(symbol_id:, file_path:, ir_node:)
        key = symbol_id.to_s
        entry = { file_path: file_path.to_s, ir_node: ir_node }
        list = @origins[key] ||= []
        return false if list.any? { |o| origin_equal?(o, entry) }

        list << entry
        true
      end
      # rubocop:enable Naming/PredicateMethod

      def origins_for(symbol_id:)
        Array(@origins[symbol_id.to_s]).map(&:dup)
      end

      def symbols
        @origins.keys
      end

      def reset_file(file_path:)
        fp = file_path.to_s
        removed = 0
        @origins.each_value do |list|
          before = list.size
          list.reject! { |o| o[:file_path] == fp }
          removed += before - list.size
        end
        @origins.reject! { |_k, v| v.empty? }
        removed
      end

      private

      def origin_equal?(left, right)
        left[:file_path] == right[:file_path] && left[:ir_node] == right[:ir_node]
      end
    end
  end
end

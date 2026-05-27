# frozen_string_literal: true

require_relative "class_node_merger"
require_relative "ir/class_node"
require_relative "symbol_graph"

module OllamaAgent
  module Topology
    # Two-phase symbol storage: staged buffer then committed +origins+ (parse/validation gated).
    class StagedGraph < SymbolGraph
      def initialize
        super
        @staged = {}
        @staged_by_file = Hash.new { |h, k| h[k] = [] }
        @promotion_blockers = {}
      end

      def stage(file_path:, ir_nodes:)
        fp = file_path.to_s
        Array(ir_nodes).each { |node| stage_node(fp, node) }
      end

      def note_parse_failure(file_path:)
        @promotion_blockers[file_path.to_s] = :parse_error
      end

      def note_validation_failure(file_path:)
        @promotion_blockers[file_path.to_s] = :validation
      end

      def promote(file_path:)
        fp = file_path.to_s
        blocker = @promotion_blockers[fp]
        return :rejected_parse_error if blocker == :parse_error
        return :rejected_validation if blocker == :validation

        entries = Array(@staged_by_file[fp]).dup
        entries.each { |entry| commit_entry(entry) }
        remove_staged_entries_for_file_path(fp)
        @promotion_blockers.delete(fp)
        :promoted
      end

      def reject(file_path:, reason:)
        remove_staged_entries_for_file_path(file_path.to_s)
        reason
      end

      def committed_origins_for(symbol_id:)
        origins_for(symbol_id: symbol_id)
      end

      def staged_origins_for(symbol_id:)
        Array(@staged[symbol_id.to_s]).map(&:dup)
      end

      # Yields committed +@origins+ bundles only (never staged). +ir_node_aggregate+ merges same-FQCN class shards.
      def committed_symbols_with_origins
        return enum_for(:committed_symbols_with_origins) unless block_given?

        @origins.each do |symbol_id, list|
          origins_dup = list.map(&:dup)
          aggregate = aggregate_ir_for_origins(origins_dup)
          yield({ symbol_id: symbol_id, origins: origins_dup, ir_node_aggregate: aggregate })
        end
      end

      private

      def stage_node(file_path, node)
        sid = symbol_id_for(node)
        entry = { symbol_id: sid, file_path: file_path, ir_node: node }
        @staged_by_file[file_path] << entry
        list = @staged[sid] ||= []
        list << { file_path: file_path, ir_node: node }
      end

      def commit_entry(entry)
        add_origin(symbol_id: entry[:symbol_id], file_path: entry[:file_path], ir_node: entry[:ir_node])
      end

      def remove_staged_entries_for_file_path(path)
        entries = @staged_by_file.delete(path) || []
        entries.each { |entry| remove_staged_origin(entry[:symbol_id], path, entry[:ir_node]) }
      end

      def remove_staged_origin(symbol_id, path, ir_node)
        list = @staged[symbol_id]
        return unless list

        list.reject! { |o| o[:file_path] == path && o[:ir_node] == ir_node }
        @staged.delete(symbol_id) if list.empty?
      end

      def aggregate_ir_for_origins(origins)
        nodes = origins.map { |o| o[:ir_node] }.uniq
        return nodes.first if nodes.one?

        merge_uniform_class_nodes(nodes) || nodes.first
      end

      def merge_uniform_class_nodes(nodes)
        class_nodes = nodes.grep(IR::ClassNode)
        return nil unless class_nodes.size == nodes.size

        fq = class_nodes.first.fqcn
        return nil unless class_nodes.all? { |n| n.fqcn == fq }

        ClassNodeMerger.merge(class_nodes)
      end
    end
  end
end

require_relative "staged_graph/symbol_ids"

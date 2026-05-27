# frozen_string_literal: true

require_relative "ir/class_node"

module OllamaAgent
  module Topology
    # Merges multiple {IR::ClassNode} shards with the same FQCN into one aggregate node.
    module ClassNodeMerger
      module_function

      def merge(nodes)
        base = nodes.min_by(&:source_path)
        methods_by_name, includes, extends, superclass = merge_traits(nodes)
        build_merged_node(base, methods_by_name, includes, extends, superclass)
      end

      def build_merged_node(base, methods_by_name, includes, extends, superclass)
        IR::ClassNode.build(
          source_path: base.source_path, source_line: base.source_line,
          origin_extractor_version: base.origin_extractor_version, fqcn: base.fqcn, superclass_fqcn: superclass,
          module_chain: base.module_chain, methods: methods_by_name.values,
          includes: includes.uniq, extends: extends.uniq
        )
      end
      private_class_method :build_merged_node

      def merge_traits(nodes)
        methods_by_name = {}
        includes = []
        extends = []
        superclass = nil
        nodes.each { |n| superclass = absorb_shard(n, superclass, methods_by_name, includes, extends) }
        [methods_by_name, includes, extends, superclass]
      end
      private_class_method :merge_traits

      def absorb_shard(node, superclass, methods_by_name, includes, extends)
        superclass = node.superclass_fqcn if node.superclass_fqcn
        includes.concat(node.includes)
        extends.concat(node.extends)
        collect_methods(node, methods_by_name)
        superclass
      end
      private_class_method :absorb_shard

      def collect_methods(node, methods_by_name)
        Array(node.methods).each do |m|
          methods_by_name[(m[:name] || m["name"]).to_s] = m
        end
      end
      private_class_method :collect_methods
    end
  end
end

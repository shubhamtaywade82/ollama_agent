# frozen_string_literal: true

require_relative "../ir/class_node"
require_relative "../ir/concern_node"
require_relative "../ir/module_node"

module OllamaAgent
  module Topology
    class Linker
      # Merges multi-origin IR for one FQCN; expands ActiveSupport::Concern includes.
      class Aggregate
        def call(ir_by_file:)
          concerns = {}
          buckets = Hash.new { |h, k| h[k] = [] }
          bucket_nodes(ir_by_file, concerns, buckets)
          buckets.transform_values { |nodes| merge_type_nodes(nodes, concerns) }
        end

        private

        def bucket_nodes(ir_by_file, concerns, buckets)
          ir_by_file.each_value do |nodes|
            Array(nodes).each { |node| bucket_one(node, concerns, buckets) }
          end
        end

        def bucket_one(node, concerns, buckets)
          case node
          when OllamaAgent::Topology::IR::ConcernNode
            concerns[node.fqcn] = node
          when OllamaAgent::Topology::IR::ClassNode, OllamaAgent::Topology::IR::ModuleNode
            buckets[node.fqcn] << node
          end
        end

        def merge_type_nodes(nodes, concerns)
          base = merge_fields(nodes)
          base.merge(concern_fields(base[:includes], concerns))
        end

        def merge_fields(nodes)
          acc = { methods_by_name: {}, includes: [], extends: [], versions: [], origins: [] }
          superclass = nil
          nodes.each do |n|
            absorb_into(acc, n)
            superclass = n.superclass_fqcn if n.respond_to?(:superclass_fqcn) && n.superclass_fqcn
          end
          assemble_merge(nodes, acc, superclass)
        end

        def absorb_into(acc, node)
          acc[:versions] << node.origin_extractor_version
          acc[:origins] << node
          acc[:includes].concat(node.includes) if node.respond_to?(:includes)
          acc[:extends].concat(node.extends) if node.respond_to?(:extends)
          merge_methods(acc[:methods_by_name], node)
        end

        def merge_methods(methods_by_name, node)
          Array(node.methods).each do |m|
            methods_by_name[(m[:name] || m["name"]).to_s] = m
          end
        end

        def assemble_merge(nodes, acc, superclass)
          {
            fqcn: nodes.first.fqcn,
            kinds: nodes.map(&:kind).uniq,
            superclass_fqcn: superclass,
            methods: acc[:methods_by_name].values,
            includes: acc[:includes].uniq,
            extends: acc[:extends].uniq,
            extractor_versions: acc[:versions].uniq,
            origins: acc[:origins]
          }
        end

        def concern_fields(includes, concerns)
          i_set = []
          c_set = []
          Array(includes).each do |inc|
            concern = concerns[inc]
            next unless concern

            i_set.concat(concern.instance_methods)
            c_set.concat(concern.class_methods)
          end
          { concern_instance_methods: i_set.uniq.sort, concern_class_methods: c_set.uniq.sort }
        end
      end
    end
  end
end

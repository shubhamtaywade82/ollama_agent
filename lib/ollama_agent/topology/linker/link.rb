# frozen_string_literal: true

module OllamaAgent
  module Topology
    class Linker
      # Raised when the same FQCN is built from incompatible extractor versions in one run.
      class LinkConflictError < StandardError; end

      # Superclass and mixin wiring over aggregated symbols.
      class Link
        def call(aggregated:, registry:)
          assert_extractor_consistency!(aggregated)
          reg = registry.is_a?(Set) ? registry : Set.new(registry)
          {
            inheritance: inheritance_map(aggregated),
            resolved_mixin_edges: mixin_edges(aggregated, reg)
          }
        end

        private

        def assert_extractor_consistency!(aggregated)
          aggregated.each do |fqcn, meta|
            versions = Array(meta[:extractor_versions]).uniq
            next if versions.size <= 1

            msg = "FQCN #{fqcn} mixes extractor versions: #{versions.sort.join(", ")}"
            raise LinkConflictError, msg
          end
        end

        def inheritance_map(aggregated)
          aggregated.transform_values { |m| m[:superclass_fqcn] }
        end

        def mixin_edges(aggregated, registry)
          edges = []
          aggregated.each { |owner, meta| absorb_mixins(edges, owner, meta, registry) }
          edges
        end

        def absorb_mixins(edges, owner, meta, registry)
          Array(meta[:resolved_includes]).each { |slot| push_edge(edges, owner, slot, registry, :include) }
          Array(meta[:resolved_extends]).each { |slot| push_edge(edges, owner, slot, registry, :extend) }
        end

        def push_edge(edges, owner, slot, registry, kind)
          return unless slot[:status] == :resolved
          return unless registry.include?(slot[:fqcn])

          edges << { from: owner, to: slot[:fqcn], kind: kind }
        end
      end
    end
  end
end

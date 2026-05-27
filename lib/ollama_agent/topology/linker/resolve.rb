# frozen_string_literal: true

require_relative "../zeitwerk_inflector"

module OllamaAgent
  module Topology
    class Linker
      # Resolves include/extend strings against the discovered FQCN registry (Zeitwerk file hints).
      class Resolve
        def initialize(workspace_root:, inflector: OllamaAgent::Topology::ZeitwerkInflector)
          @workspace_root = workspace_root ? File.expand_path(workspace_root) : nil
          @inflector = inflector
        end

        def resolve_includes(graph:, registry:)
          reg = registry.is_a?(Set) ? registry : Set.new(registry)
          graph.transform_values { |meta| resolve_entry(meta, reg) }
        end

        private

        def resolve_entry(meta, reg)
          inc = Array(meta[:includes]).map { |raw| resolve_ref(raw.to_s, reg) }
          ext = Array(meta[:extends]).map { |raw| resolve_ref(raw.to_s, reg) }
          meta.merge(resolved_includes: inc, resolved_extends: ext)
        end

        def resolve_ref(raw, reg)
          return { raw: raw, status: :resolved, fqcn: raw } if reg.include?(raw)
          return { raw: raw, status: :unresolved } unless @workspace_root && zeitwerk_file_exists?(raw)

          { raw: raw, status: :resolved, fqcn: raw }
        end

        def zeitwerk_file_exists?(fqcn)
          roots = OllamaAgent::Topology::ZeitwerkInflector::DEFAULT_ROOTS.map { |r| File.join(@workspace_root, r) }
          @inflector.constant_to_file_pattern(fqcn: fqcn, root_paths: roots).any? { |p| File.file?(p) }
        end
      end
    end
  end
end

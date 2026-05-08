# frozen_string_literal: true

require_relative "extractors/ruby_semantic_extractor"
require_relative "staged_graph"
require_relative "zeitwerk_inflector"

module OllamaAgent
  module Topology
    # Orchestrates discovery → extract → stage → aggregate → resolve → link → validate → promote.
    class Linker
      def initialize(workspace_root:, staged_graph:, extractor: nil, inflector: OllamaAgent::Topology::ZeitwerkInflector)
        @workspace_root = File.expand_path(workspace_root.to_s)
        @staged_graph = staged_graph
        @extractor = extractor || Extractors::RubySemanticExtractor.new
        @inflector = inflector
      end

      def run(roots:)
        extracted = extract_from_roots(roots)
        stage_extract_results(extracted)
        analysis = analyze_graph(extracted)
        apply_promotions(extracted, analysis[:validation])
        build_result(extracted, analysis)
      end

      private

      def extract_from_roots(roots)
        root_abs = Array(roots).map { |r| File.join(@workspace_root, r.to_s) }
        discovered = Discovery.find_files(roots: root_abs)
        extracted = Extract.new(extractor: @extractor).call(files: discovered)
        extracted[:discovered] = discovered
        extracted
      end

      def stage_extract_results(extracted)
        extracted[:parse_errors].each_key { |fp| @staged_graph.note_parse_failure(file_path: fp) }
        extracted[:ir_by_file].each { |fp, nodes| @staged_graph.stage(file_path: fp, ir_nodes: nodes) }
      end

      def analyze_graph(extracted)
        aggregated = Aggregate.new.call(ir_by_file: extracted[:ir_by_file])
        registry = Set.new(aggregated.keys)
        resolved = Resolve.new(workspace_root: @workspace_root, inflector: @inflector).resolve_includes(
          graph: aggregated,
          registry: registry
        )
        linked = Link.new.call(aggregated: resolved, registry: registry)
        validation = Validate.new.call(aggregated: aggregated, linked: linked)
        { aggregated: aggregated, resolved: resolved, linked: linked, validation: validation }
      end

      def apply_promotions(extracted, validation)
        mark_validation_failures(extracted, validation) unless validation[:valid]
        promote_all_paths(extracted)
      end

      def mark_validation_failures(extracted, validation)
        affected = validation[:errors].flat_map { |e| Array(e[:file_paths]) }.compact.uniq
        affected = extracted[:ir_by_file].keys if affected.empty?
        extracted[:ir_by_file].each_key do |fp|
          @staged_graph.note_validation_failure(file_path: fp) if affected.include?(fp)
        end
      end

      def promote_all_paths(extracted)
        keys = (extracted[:ir_by_file].keys + extracted[:parse_errors].keys).uniq
        keys.each { |fp| @staged_graph.promote(file_path: fp) }
      end

      def build_result(extracted, analysis)
        {
          discovered: extracted[:discovered],
          parse_errors: extracted[:parse_errors],
          aggregated: analysis[:aggregated],
          validation: analysis[:validation],
          resolved: analysis[:resolved],
          linked: analysis[:linked]
        }
      end
    end
  end
end

require_relative "linker/discovery"
require_relative "linker/extract"
require_relative "linker/aggregate"
require_relative "linker/resolve"
require_relative "linker/link"
require_relative "linker/validate"

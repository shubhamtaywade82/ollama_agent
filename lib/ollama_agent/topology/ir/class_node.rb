# frozen_string_literal: true

module OllamaAgent
  module Topology
    module IR
      # Ruby class definition (+include+ / +extend+ FQCN strings; +methods+ are signature hashes).
      # rubocop:disable Lint/DataDefineOverride -- IR field name +methods+ is part of the public contract.
      ClassNode = Data.define(
        :kind,
        :source_path,
        :source_line,
        :origin_extractor_version,
        :fqcn,
        :superclass_fqcn,
        :module_chain,
        :methods,
        :includes,
        :extends
      ) do
        # rubocop:disable Metrics/ParameterLists -- factory mirrors Data members explicitly.
        def self.build(
          source_path:,
          source_line:,
          origin_extractor_version:,
          fqcn:,
          superclass_fqcn: nil,
          module_chain: [],
          methods: [],
          includes: [],
          extends: []
        )
          # rubocop:enable Metrics/ParameterLists
          new(:class, source_path.to_s, Integer(source_line), origin_extractor_version.to_s, fqcn.to_s,
              superclass_fqcn&.to_s, Array(module_chain).map(&:to_s).freeze, IR.deep_freeze_hashes(methods),
              Array(includes).map(&:to_s).freeze, Array(extends).map(&:to_s).freeze)
        end
      end
      # rubocop:enable Lint/DataDefineOverride
    end
  end
end

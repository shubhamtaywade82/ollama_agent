# frozen_string_literal: true

module OllamaAgent
  module Topology
    module IR
      # rubocop:disable Lint/DataDefineOverride -- IR field name +methods+ is part of the public contract.
      ModuleNode = Data.define(
        :kind,
        :source_path,
        :source_line,
        :origin_extractor_version,
        :fqcn,
        :module_chain,
        :methods
      ) do
        # rubocop:disable Metrics/ParameterLists
        def self.build(
          source_path:,
          source_line:,
          origin_extractor_version:,
          fqcn:,
          module_chain: [],
          methods: []
        )
          # rubocop:enable Metrics/ParameterLists
          new(
            :module,
            source_path.to_s,
            Integer(source_line),
            origin_extractor_version.to_s,
            fqcn.to_s,
            Array(module_chain).map(&:to_s).freeze,
            IR.deep_freeze_hashes(methods)
          )
        end
      end
      # rubocop:enable Lint/DataDefineOverride
    end
  end
end

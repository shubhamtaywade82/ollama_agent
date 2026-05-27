# frozen_string_literal: true

module OllamaAgent
  module Topology
    module IR
      ConcernNode = Data.define(
        :kind,
        :source_path,
        :source_line,
        :origin_extractor_version,
        :fqcn,
        :included_modules,
        :class_methods,
        :instance_methods
      ) do
        # rubocop:disable Metrics/ParameterLists
        def self.build(
          source_path:,
          source_line:,
          origin_extractor_version:,
          fqcn:,
          included_modules: [],
          class_methods: [],
          instance_methods: []
        )
          # rubocop:enable Metrics/ParameterLists
          new(
            :concern,
            source_path.to_s,
            Integer(source_line),
            origin_extractor_version.to_s,
            fqcn.to_s,
            Array(included_modules).map(&:to_s).freeze,
            Array(class_methods).map(&:to_s).freeze,
            Array(instance_methods).map(&:to_s).freeze
          )
        end
      end
    end
  end
end

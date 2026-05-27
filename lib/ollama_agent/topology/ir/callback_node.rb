# frozen_string_literal: true

module OllamaAgent
  module Topology
    module IR
      CallbackNode = Data.define(
        :kind,
        :source_path,
        :source_line,
        :origin_extractor_version,
        :owner_fqcn,
        :phase,
        :method_name
      ) do
        # rubocop:disable Metrics/ParameterLists
        def self.build(
          source_path:,
          source_line:,
          origin_extractor_version:,
          owner_fqcn:,
          phase:,
          method_name:
        )
          # rubocop:enable Metrics/ParameterLists
          new(
            :callback,
            source_path.to_s,
            Integer(source_line),
            origin_extractor_version.to_s,
            owner_fqcn.to_s,
            phase.to_s,
            method_name.to_s
          )
        end
      end
    end
  end
end

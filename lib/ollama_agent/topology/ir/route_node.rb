# frozen_string_literal: true

module OllamaAgent
  module Topology
    module IR
      RouteNode = Data.define(
        :kind,
        :source_path,
        :source_line,
        :origin_extractor_version,
        :verb,
        :path,
        :controller_fqcn,
        :action_name
      ) do
        # rubocop:disable Metrics/ParameterLists
        def self.build(
          source_path:,
          source_line:,
          origin_extractor_version:,
          verb:,
          path:,
          controller_fqcn:,
          action_name:
        )
          # rubocop:enable Metrics/ParameterLists
          new(
            :route,
            source_path.to_s,
            Integer(source_line),
            origin_extractor_version.to_s,
            verb.to_s.upcase,
            path.to_s,
            controller_fqcn.to_s,
            action_name.to_s
          )
        end
      end
    end
  end
end

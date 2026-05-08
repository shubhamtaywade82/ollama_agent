# frozen_string_literal: true

module OllamaAgent
  module Topology
    module IR
      EventPublisherNode = Data.define(
        :kind,
        :source_path,
        :source_line,
        :origin_extractor_version,
        :fqcn,
        :event_name,
        :payload_schema_ref
      ) do
        # rubocop:disable Metrics/ParameterLists
        def self.build(
          source_path:,
          source_line:,
          origin_extractor_version:,
          fqcn:,
          event_name:,
          payload_schema_ref: nil
        )
          # rubocop:enable Metrics/ParameterLists
          new(
            :event_publisher,
            source_path.to_s,
            Integer(source_line),
            origin_extractor_version.to_s,
            fqcn.to_s,
            event_name.to_s,
            payload_schema_ref&.to_s
          )
        end
      end
    end
  end
end

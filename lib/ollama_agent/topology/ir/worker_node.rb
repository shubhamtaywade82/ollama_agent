# frozen_string_literal: true

module OllamaAgent
  module Topology
    module IR
      WorkerNode = Data.define(
        :kind,
        :source_path,
        :source_line,
        :origin_extractor_version,
        :fqcn,
        :queue,
        :perform_signature
      ) do
        # rubocop:disable Metrics/ParameterLists
        def self.build(
          source_path:,
          source_line:,
          origin_extractor_version:,
          fqcn:,
          queue:,
          perform_signature: {}
        )
          # rubocop:enable Metrics/ParameterLists
          new(
            :worker,
            source_path.to_s,
            Integer(source_line),
            origin_extractor_version.to_s,
            fqcn.to_s,
            queue.to_s,
            IR.deep_freeze_hash(perform_signature)
          )
        end
      end
    end
  end
end

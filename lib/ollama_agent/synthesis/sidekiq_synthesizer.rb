# frozen_string_literal: true

require_relative "integration_extractor"

module OllamaAgent
  module Synthesis
    # Aggregates worker FQCNs by queue from {IntegrationExtractor} output.
    class SidekiqSynthesizer
      def initialize(integration_extractor:)
        @integration_extractor = integration_extractor
      end

      def synthesize
        scan = @integration_extractor.extract
        by_queue = Hash.new { |h, k| h[k] = [] }
        scan.workers.each { |w| by_queue[w.queue] << w.fqcn }
        by_queue
          .transform_values { |fqs| fqs.uniq.sort }
          .sort
          .to_h
      end
    end
  end
end

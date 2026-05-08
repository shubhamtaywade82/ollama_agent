# frozen_string_literal: true

module OllamaAgent
  module Synthesis
    # Immutable snapshot of integration-relevant IR derived from the committed topology graph.
    IntegrationScan = Data.define(:routes, :workers, :event_publishers, :ar_models)
  end
end

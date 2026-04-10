# frozen_string_literal: true

module OllamaAgent
  module ToolRuntime
    # Strategy protocol for {Loop}: produce the next plan hash from context and memory.
    #
    # @example Contract
    #   def next_step(context:, memory:, registry:) -> Hash
    module PlanExtractor
    end
  end
end

# frozen_string_literal: true

module TradingAgent
  # Minimal synchronous pub/sub bus that wires the pipeline stages together
  # (stream tick -> state -> strategy -> evaluator). Kept dependency-free and
  # deterministic; swap for an async implementation in Phase 4 if needed.
  class EventBus
    def initialize
      @subscribers = Hash.new { |h, k| h[k] = [] }
    end

    # @param topic [String, Symbol]
    def subscribe(topic, &handler)
      raise ArgumentError, "handler block required" unless block_given?

      @subscribers[topic.to_s] << handler
      self
    end

    # @param topic [String, Symbol]
    # @param payload [Object]
    def publish(topic, payload = nil)
      @subscribers[topic.to_s].each { |h| h.call(payload) }
      nil
    end
  end
end

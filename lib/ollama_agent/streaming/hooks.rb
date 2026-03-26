# frozen_string_literal: true

module OllamaAgent
  module Streaming
    # Lightweight event bus for agent lifecycle events.
    # All layers share one Hooks instance per Agent run.
    class Hooks
      EVENTS = %i[on_token on_chunk on_tool_call on_tool_result on_complete on_error on_retry].freeze

      def initialize
        @handlers = Hash.new { |h, k| h[k] = [] }
      end

      # Register a handler block for a named event.
      def on(event, &block)
        @handlers[event] << block
      end

      # Fire all handlers for the event with the given payload hash.
      # Handler errors are swallowed to prevent a bad subscriber from crashing the agent.
      def emit(event, payload)
        @handlers[event].each do |handler|
          handler.call(payload)
        rescue StandardError
          nil
        end
      end

      # Returns true if at least one handler is registered for the event.
      def subscribed?(event)
        @handlers[event].any?
      end
    end
  end
end

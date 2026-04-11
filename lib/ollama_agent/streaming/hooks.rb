# frozen_string_literal: true

module OllamaAgent
  module Streaming
    # Lightweight event bus for agent lifecycle events.
    # All layers share one Hooks instance per Agent run.
    class Hooks
      EVENTS = %i[
        on_token on_thinking on_chunk on_tool_call on_tool_result on_assistant_message on_complete on_error on_retry
      ].freeze

      MISSING_BLOCK_MESSAGE = "Hooks require a block when registering a handler"

      def initialize
        @handlers = Hash.new { |h, k| h[k] = [] }
      end

      # Register a handler block for a named event.
      def on(event, &block)
        raise ArgumentError, MISSING_BLOCK_MESSAGE unless block_given?

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

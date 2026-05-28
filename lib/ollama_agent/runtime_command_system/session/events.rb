# frozen_string_literal: true

module OllamaAgent
  module RuntimeCommandSystem
    module Session
      class Events
        def initialize
          @handlers = Hash.new { |h, k| h[k] = [] }
        end

        def on(event, &block)
          raise ArgumentError, "block required" unless block_given?

          @handlers[event.to_sym] << block
          self
        end

        def emit(event, payload = {})
          @handlers[event.to_sym].each do |handler|
            handler.call(payload)
          rescue StandardError
            nil
          end
        end

        def subscribed?(event)
          @handlers[event.to_sym].any?
        end
      end
    end
  end
end

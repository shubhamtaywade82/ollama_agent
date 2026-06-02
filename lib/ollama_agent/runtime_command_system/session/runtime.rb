# frozen_string_literal: true

require_relative "events"

module OllamaAgent
  module RuntimeCommandSystem
    module Session
      class Runtime
        attr_reader :events, :agent

        def initialize(agent:)
          @agent  = agent
          @events = Events.new
        end

        def active_model
          @agent.model
        end

        def active_provider
          @agent.provider_name
        end

        def switch_model!(name, descriptor: nil)
          @agent.assign_chat_model!(name)
          @events.emit(:model_switched, model: name, descriptor: descriptor)
          name
        end

        def state
          { model: active_model, provider: active_provider }
        end

        def export_state
          state.merge(timestamp: Time.now.iso8601)
        end
      end
    end
  end
end

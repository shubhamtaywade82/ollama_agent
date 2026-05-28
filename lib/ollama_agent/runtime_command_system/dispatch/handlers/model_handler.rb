# frozen_string_literal: true

module OllamaAgent
  module RuntimeCommandSystem
    module Dispatch
      module Handlers
        class ModelHandler
          def call(ast:, session:)
            name = ast.arguments.first&.value.to_s.strip
            raise ArgumentError, "Missing model name — usage: /model <name>" if name.empty?

            descriptor = Providers::ModelRegistry.find(name, agent: session.agent)
            session.switch_model!(name, descriptor: descriptor)
            { model: name, descriptor: descriptor }
          end
        end
      end
    end
  end
end

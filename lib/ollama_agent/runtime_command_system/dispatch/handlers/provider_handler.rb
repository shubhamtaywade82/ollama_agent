# frozen_string_literal: true

module OllamaAgent
  module RuntimeCommandSystem
    module Dispatch
      module Handlers
        class ProviderHandler
          def call(ast:, session:)
            provider = ast.arguments.first&.value.to_s.strip
            hint = provider.empty? ? "<name>" : provider
            raise NotImplementedError,
                  "Provider switching requires session restart. " \
                  "Use: ollama_agent ask --provider #{hint}"
          end
        end
      end
    end
  end
end

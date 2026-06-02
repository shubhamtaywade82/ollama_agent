# frozen_string_literal: true

require_relative "suggestion"
require_relative "../errors"
require_relative "../providers/registry"
require_relative "../providers/model_registry"

module OllamaAgent
  module RuntimeCommandSystem
    module Completers
      class BaseCompleter
        def suggestions(**)
          []
        end
      end

      class ModelCompleter < BaseCompleter
        def suggestions(ast:, session: {}, **)
          token = current_token(ast)
          models = session[:model_registry_cache] ||= Providers::ModelRegistry.all(agent: session[:agent])
          select_matches(models, token).map do |model|
            Suggestion.new(
              text: model.name,
              type: :model,
              description: model_metadata(model),
              metadata: { provider: model.provider, context_size: model.context_size, status: model.status },
              capabilities: model.capabilities - [:chat],
              replacement_start: current_argument_start(ast)
            )
          end
        end

        private

        def select_matches(models, token)
          query = token.downcase
          models.select { |model| matches_model?(model, query) }
                .sort_by { |model| sort_key(model, query) }
        end

        def matches_model?(model, query)
          query.empty? ||
            model.name.downcase.include?(query) ||
            model.provider.downcase.include?(query)
        end

        def sort_key(model, query)
          name = model.name.downcase
          [name.start_with?(query) ? 0 : 1, model.status == "loaded" ? 0 : 1, name]
        end

        def model_metadata(model)
          parts = [model.provider]
          parts << "#{model.context_size / 1000}k" if model.context_size.positive?
          parts << model.status if model.status && model.status != "available"
          parts.join(" • ")
        end

        def current_token(ast)
          ast.current_argument&.value.to_s
        end

        def current_argument_start(ast)
          ast.current_argument&.position || ast.raw.length
        end
      end

      class ProviderCompleter < BaseCompleter
        def suggestions(ast:, **)
          token = ast.current_argument&.value.to_s.downcase
          Providers::Registry.known_names.sort.grep(/#{Regexp.escape(token)}/).map do |provider|
            Suggestion.new(
              text: provider,
              type: :provider,
              description: "provider",
              replacement_start: ast.current_argument&.position || ast.raw.length
            )
          end
        end
      end
    end
  end
end

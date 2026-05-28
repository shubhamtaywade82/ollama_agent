# frozen_string_literal: true

module OllamaAgent
  module RuntimeCommandSystem
    module Dispatch
      class Dispatcher
        def initialize
          @handlers = {}
        end

        def register(command_name, handler)
          @handlers[normalize(command_name)] = handler
          self
        end

        def handles?(command_name)
          @handlers.key?(normalize(command_name))
        end

        def dispatch(ast, session:)
          handler = @handlers[normalize(ast.name)]
          return { handled: false } unless handler

          result = handler.call(ast: ast, session: session)
          (result || {}).merge(handled: true)
        end

        private

        def normalize(name)
          name.to_s.delete_prefix("/").downcase
        end
      end
    end
  end
end

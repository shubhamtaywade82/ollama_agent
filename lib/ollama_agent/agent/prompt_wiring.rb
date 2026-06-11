# frozen_string_literal: true

module OllamaAgent
  class Agent
    module PromptWiring
      private

      def system_prompt
        @prompt_builder.system_prompt
      end
    end
  end
end
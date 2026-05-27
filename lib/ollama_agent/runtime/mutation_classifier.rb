# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # Heuristic classification for saga compensation strategy (blob restore lands in E8).
    module MutationClassifier
      module_function

      # @param intent [Hash]
      # @return [:reversible, :compensatable, :irreversible]
      def classify(intent)
        kind = intent[:kind] || intent["kind"]
        case kind.to_s
        when "atomic_write"
          :reversible
        when "http_post", "shell_exec"
          :irreversible
        else
          :compensatable
        end
      end
    end
  end
end

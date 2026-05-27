# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # Supported execution modes for kernel orchestration paths.
    module ExecutionMode
      NORMAL = "normal"
      REPLAY = "replay"
      VALIDATION = "validation"
      DRY_RUN = "dry_run"
      SHADOW = "shadow"

      ALL = [NORMAL, REPLAY, VALIDATION, DRY_RUN, SHADOW].freeze

      module_function

      def valid?(mode)
        ALL.include?(mode.to_s)
      end
    end
  end
end

# frozen_string_literal: true

require_relative "execution_mode"

module OllamaAgent
  module Runtime
    # Immutable execution context carried through runtime boundaries.
    class ExecutionContext
      attr_reader :mode, :workspace_root, :manifest_id, :metadata

      def initialize(mode:, workspace_root:, manifest_id:, metadata: {})
        raise ArgumentError, "invalid execution mode: #{mode}" unless ExecutionMode.valid?(mode)

        @mode = mode.to_s
        @workspace_root = workspace_root
        @manifest_id = manifest_id
        @metadata = metadata.dup.freeze
      end
    end
  end
end

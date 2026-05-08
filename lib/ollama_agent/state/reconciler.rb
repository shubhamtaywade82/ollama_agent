# frozen_string_literal: true

require_relative "git_changed_paths"

module OllamaAgent
  module State
    # Compares pre/post workspace fingerprints and surfaces git-visible drift.
    class Reconciler
      attr_reader :fingerprint_calculator

      def initialize(workspace_root:, fingerprint_calculator:)
        @workspace_root = workspace_root.to_s
        @fingerprint_calculator = fingerprint_calculator
      end

      def reconcile(pre_fingerprint:, post_state_observer:)
        post_fp = post_state_observer.call.to_s
        pre = pre_fingerprint.to_s
        drifted = pre != post_fp
        changed_files = drifted ? GitChangedPaths.list(@workspace_root) : []
        {
          fingerprint_drifted: drifted,
          changed_files: changed_files,
          conflicts: []
        }
      end
    end
  end
end

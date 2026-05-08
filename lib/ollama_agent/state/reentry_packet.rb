# frozen_string_literal: true

module OllamaAgent
  module State
    # Bounded post-escalation handoff packet for local planner re-entry.
    class ReentryPacket
      attr_reader :reason, :workspace_fingerprint, :changed_files, :summary

      def initialize(reason:, workspace_fingerprint:, changed_files:, summary:)
        @reason = reason
        @workspace_fingerprint = workspace_fingerprint
        @changed_files = Array(changed_files).sort.freeze
        @summary = summary
      end

      def to_h
        {
          "reason" => reason,
          "workspace_fingerprint" => workspace_fingerprint,
          "changed_files" => changed_files,
          "summary" => summary
        }
      end
    end
  end
end

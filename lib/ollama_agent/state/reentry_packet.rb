# frozen_string_literal: true

require "json"

require_relative "git_changed_paths"

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

      class << self
        def build(reason:, workspace_root:, ast_summarizer:, fingerprint_calculator:, touched_methods: [])
          fingerprint = fingerprint_calculator.compute.to_s
          changed = GitChangedPaths.list(workspace_root)
          summary = summary_json(ast_summarizer, changed, touched_methods)
          new(
            reason: reason,
            workspace_fingerprint: fingerprint,
            changed_files: changed,
            summary: summary
          )
        end

        private

        def summary_json(ast_summarizer, changed_files, touched_methods)
          return "{}" if changed_files.empty?

          payload = ast_summarizer.summarize(file_paths: changed_files, touched_methods: touched_methods)
          JSON.generate(payload)
        end
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

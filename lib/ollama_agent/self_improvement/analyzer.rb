# frozen_string_literal: true

require_relative "../agent"

module OllamaAgent
  module SelfImprovement
    # Runs a read-only agent pass to review the gem (no edits).
    class Analyzer
      DEFAULT_PROMPT = <<~PROMPT
        Perform a self-review of this gem: architecture, tests, clarity, and risks.
        Scan for TODO/FIXME/HACK and call out the highest-impact follow-ups.
        Use tools to inspect real files; finish with prioritized, actionable recommendations.
      PROMPT

      # Mode 2 (interactive): full tool loop on the real tree; user confirms each patch like `ask`.
      INTERACTIVE_PROMPT = <<~PROMPT
        You are improving the ollama_agent gem in this working tree (not a sandbox).
        The user message may begin with "## Static analysis (ruby_mastery)" from tooling; confirm against the tree.
        Use list_files, search_code, and read_file, then apply small unified diffs with edit_file.
        Keep changes reviewable; prefer tests, docs, and clarity fixes; address TODO/FIXME/HACK when safe.
        When finished, summarize what you changed or suggested next.
      PROMPT

      def initialize(agent)
        @agent = agent
      end

      def run(prompt = DEFAULT_PROMPT, preamble: nil)
        body = [preamble, prompt].compact.map(&:to_s).reject(&:empty?).join("\n\n")
        @agent.run(body)
      end
    end
  end
end

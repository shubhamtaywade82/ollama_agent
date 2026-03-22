# frozen_string_literal: true

require_relative "../agent"

module OllamaAgent
  module SelfImprovement
    # Runs a read-only agent pass to review the gem (no edits).
    class Analyzer
      DEFAULT_PROMPT = <<~PROMPT
        Perform a self-review of this gem: architecture, tests, clarity, and risks.
        Use tools to inspect real files; finish with prioritized, actionable recommendations.
      PROMPT

      # Mode 2 (interactive): full tool loop on the real tree; user confirms each patch like `ask`.
      INTERACTIVE_PROMPT = <<~PROMPT
        You are improving the ollama_agent gem in this working tree (not a sandbox).
        Use list_files, search_code, and read_file, then apply small unified diffs with edit_file.
        Keep changes reviewable; prefer tests, docs, and clarity fixes.
        When finished, summarize what you changed or suggested next.
      PROMPT

      def initialize(agent)
        @agent = agent
      end

      def run(prompt = DEFAULT_PROMPT)
        @agent.run(prompt)
      end
    end
  end
end

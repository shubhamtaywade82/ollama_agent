# frozen_string_literal: true

require "pathname"

module OllamaAgent
  # Validates unified diffs: hunk headers and path alignment with edit_file (applyability is patch --dry-run).
  class DiffPathValidator
    # Legacy context-diff hunks (`--- N,M ----`) are not unified diffs; models sometimes emit them by mistake.
    CONTEXT_DIFF_HUNK = /^\s*---\s+\d+\s*,\s*\d+\s*----\s*$/m

    def self.call(diff, root, target_path)
      new(diff, root, target_path).validate
    end

    # Normalizes newlines and escaped "\\n" sequences models sometimes send in tool args.
    def self.normalize_diff(diff)
      d = diff.to_s
      d = d.gsub("\r\n", "\n").gsub("\r", "\n")
      d = d.gsub("\\\\n", "\n").gsub("\\n", "\n") if d.include?("\\n") && !d.include?("\n")
      # Strip trailing commas on ---/+++ lines (models copy commas from bad examples).
      d = d.gsub(/^((?:---|\+\+\+)[^\n]+),\s*$/m, "\\1")
      # Split "--- a/foo @@ -1,3" when glued on one line (common LLM mistake).
      d.gsub(/(\S)\s(@@ -\d[^\n]*)/, "\\1\n\\2")
    end

    def initialize(diff, root, target_path)
      @diff = self.class.normalize_diff(diff)
      @root = File.expand_path(root)
      @target_path = target_path
    end

    # @return [String, nil] error message, or nil if the diff is acceptable
    def validate
      return "Diff is empty." if @diff.strip.empty?
      return "edit_file path is missing or empty." if @target_path.nil? || @target_path.to_s.strip.empty?

      err = context_diff_hunk_error
      return err if err

      err = header_order_error
      return err if err

      err = structure_error
      return err if err

      path_alignment_error
    end

    private

    def context_diff_hunk_error
      return nil unless @diff.match?(CONTEXT_DIFF_HUNK)

      <<~MSG.strip
        This patch uses a legacy context-diff hunk line (`--- N,M ----`). Unified diffs need a hunk header that starts
        with two at-signs, e.g. `@@ -1,3 +1,3 @@`, immediately after the `+++ b/<path>` line—not `---` with numbers.
        Rebuild the diff in the same shape as `git diff` output.
      MSG
    end

    def header_order_error
      lines = @diff.lines
      idx_plus = lines.index { |l| l.start_with?("+++ ") }
      idx_hunk = lines.index { |l| l.start_with?("@@") }
      return nil if idx_hunk.nil?

      return nil if idx_plus && idx_plus < idx_hunk

      <<~MSG.strip
        A unified diff must list --- a/<path>, then +++ b/<path>, then @@ ... @@ before any changed lines.
        Do not put @@ on the line right after --- without a +++ line; use the same order as `git diff`.
      MSG
    end

    def structure_error
      return nil if hunk_present?

      missing_hunk_message
    end

    def hunk_present?
      @diff.match?(/^@@/m) || @diff.start_with?("@@")
    end

    def missing_hunk_message
      "Unified diff is incomplete: include a hunk header line starting with @@ (e.g. @@ -1,3 +1,3 @@) " \
        "after --- and +++ file headers."
    end

    def path_alignment_error
      expected = relative_under_root(@target_path)
      return "Path is not under project root." if expected.nil?

      diff_paths = plus_paths_from_diff
      return "Unified diff must include +++ lines (e.g. +++ b/README.md)." if diff_paths.empty?

      return nil if diff_paths.any? { |p| normalize_repo_relative(p) == expected }

      <<~MSG.strip
        The diff's files (#{diff_paths.join(", ")}) do not match edit_file path #{expected.inspect}.
        Regenerate the unified diff so --- and +++ name that same file (e.g. --- a/README.md and +++ b/README.md).
      MSG
    end

    def relative_under_root(path)
      return nil if path.nil? || path.to_s.strip.empty?

      resolved = Pathname(path.to_s).expand_path(@root).to_s
      return nil unless resolved == @root || resolved.start_with?(@root + File::SEPARATOR)

      Pathname(resolved).relative_path_from(Pathname(@root)).cleanpath.to_s
    end

    def plus_paths_from_diff
      paths = []
      @diff.each_line do |line|
        next unless line.start_with?("+++ ")

        rest = line[4..].strip
        next if rest == File::NULL

        rest = rest.sub(%r{\Ab/}, "").sub(%r{\Aa/}, "")
        paths << rest
      end
      paths.uniq
    end

    def normalize_repo_relative(path)
      Pathname(path).cleanpath.to_s
    end
  end
end

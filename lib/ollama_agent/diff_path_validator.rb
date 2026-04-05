# frozen_string_literal: true

require "pathname"

module OllamaAgent
  # Validates unified diffs: hunk headers and path alignment with edit_file (applyability is patch --dry-run).
  # rubocop:disable Metrics/ClassLength -- normalization helpers live alongside validation
  class DiffPathValidator
    # Legacy context-diff hunks (`--- N,M ----`) are not unified diffs; models sometimes emit them by mistake.
    CONTEXT_DIFF_HUNK = /^\s*---\s+\d+\s*,\s*\d+\s*----\s*$/m

    def self.call(diff, root, target_path)
      new(diff, root, target_path).validate
    end

    # Normalizes newlines and escaped "\\n" sequences models sometimes send in tool args.
    def self.normalize_diff(diff)
      d = normalize_newlines(diff.to_s)
      d = expand_escaped_newlines_when_no_real_newlines(d)
      d = strip_cursor_patch_markers(d)
      d = strip_trailing_commas_on_headers(d)
      d = split_glued_hunk_headers(d)
      ensure_trailing_newline(d)
    end

    def self.normalize_newlines(diff)
      diff.gsub("\r\n", "\n").gsub("\r", "\n")
    end

    def self.expand_escaped_newlines_when_no_real_newlines(diff)
      return diff unless diff.include?("\\n") && !diff.include?("\n")

      diff.gsub("\\\\n", "\n").gsub("\\n", "\n")
    end

    def self.strip_trailing_commas_on_headers(diff)
      diff.gsub(/^((?:---|\+\+\+)[^\n]+),\s*$/m, "\\1")
    end

    def self.split_glued_hunk_headers(diff)
      diff.gsub(/(\S)\s(@@ -\d[^\n]*)/, "\\1\n\\2")
    end

    def self.ensure_trailing_newline(diff)
      return diff if diff.empty? || diff.end_with?("\n")

      "#{diff}\n"
    end

    def self.strip_cursor_patch_markers(diff)
      # Multiline `/m` so `^` matches each line; strips Cursor-style trailers that are not valid patch input.
      diff.gsub(/^\s*\*\*\*\s*(?:Begin|End)\s+Patch\s*$/im, "")
          .gsub(/^\s*(?:Begin|End)\s+Patch\s*$/im, "")
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
        Put a +++ b/<file> line before the first @@ hunk (e.g. +++ b/README.md); do not place @@ immediately after --- alone.
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
  # rubocop:enable Metrics/ClassLength
end

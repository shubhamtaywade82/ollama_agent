# frozen_string_literal: true

require "open3"

module OllamaAgent
  # patch(1) dry-run and apply with stderr surfaced to the model.
  module PatchSupport
    private

    def patch_dry_run(diff)
      output, status = Open3.capture2e(
        "patch", "-p1", "-f", "-d", @root, "--dry-run",
        stdin_data: diff
      )
      return nil if status.success?

      return nil if patch_dry_run_unsupported?(output)

      patch_failure_message(output, dry_run: true)
    end

    def patch_dry_run_unsupported?(stderr)
      stderr.to_s.match?(/unrecognized\s+option|unknown\s+option|invalid\s+option/i)
    end

    def patch_failure_message(output, dry_run:)
      detail = output.to_s.strip
      intro = dry_run ? "Patch does not apply to the current tree (dry-run)." : "Patch failed to apply."
      hint = patch_stderr_hint(detail)

      msg = <<~MSG.strip
        #{intro}
        #{detail}

        Re-read the file with read_file, then rebuild the diff using exact lines from that file (not placeholders).
        The @@ hunk line counts must match the hunk body the way git diff would emit them.
      MSG
      hint.empty? ? msg : "#{msg}\n#{hint}"
    end

    def patch_stderr_hint(detail)
      [
        hint_legacy_context_diff(detail),
        hint_garbage_markers(detail),
        hint_markdown_bullets(detail)
      ].compact.join(" ")
    end

    def hint_legacy_context_diff(detail)
      return nil unless detail.match?(/---\s+\d+\s*,\s*\d+\s*----/i)

      "If you see `--- N,M ----`, use a unified hunk line starting with @@ (e.g. @@ -1,3 +1,3 @@)."
    end

    def hint_garbage_markers(detail)
      return nil unless detail.match?(/Only garbage|ends in middle of line/i)

      "Remove lines like `*** End Patch` / `*** Begin Patch`; they are not part of unified diff."
    end

    def hint_markdown_bullets(detail)
      return nil unless detail.match?(/malformed patch/i)

      "Markdown bullets: new lines that begin with `-` in the file must appear as `+ - text` in the diff."
    end

    def apply_patch(diff)
      output, status = Open3.capture2e(
        "patch", "-p1", "-f", "-d", @root,
        stdin_data: diff
      )

      return "Patch applied successfully." if status.success?

      patch_failure_message(output, dry_run: false)
    end
  end
end

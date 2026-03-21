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
      return "" unless detail.match?(/malformed patch|---\s+\d+\s*,\s*\d+\s*----/i)

      "If you see `--- N,M ----`, replace it with a unified hunk line starting with @@ (e.g. @@ -1,3 +1,3 @@)."
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

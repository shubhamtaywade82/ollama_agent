# frozen_string_literal: true

module OllamaAgent
  # Classifies a proposed unified diff for semi-automatic patch approval (obvious vs risky).
  module PatchRisk
    FORBIDDEN_PATTERNS = [
      /\beval\s*\(/,
      /`rm\s+-rf/,
      /system\s*\(\s*["']sudo/,
      /\bFile\.delete\b/,
      /\bKernel\.exec\b/
    ].freeze

    LARGE_DIFF_LINES = 80

    module_function

    def forbidden?(diff)
      FORBIDDEN_PATTERNS.any? { |pattern| diff.match?(pattern) }
    end

    # Returns :auto_approve (no prompt) or :require_confirmation (prompt when confirm_patches is on).
    def assess(path, diff)
      relative = path.to_s.tr("\\", "/")

      return :require_confirmation if risky?(relative, diff)

      return :auto_approve if obvious_path?(relative)
      return :auto_approve if safe_spec_change?(relative, diff)

      :require_confirmation
    end

    def risky?(relative, diff)
      forbidden?(diff) ||
        critical_path?(relative) ||
        large_diff?(diff) ||
        critical_lib_file?(relative)
    end

    def large_diff?(diff, limit: LARGE_DIFF_LINES)
      diff.scan(/^[-+][^-+]/).size > limit
    end

    def obvious_path?(relative)
      relative.end_with?(".md") || relative.start_with?("docs/")
    end

    def safe_spec_change?(relative, diff)
      relative.start_with?("spec/") && !large_diff?(diff, limit: 40)
    end

    def critical_lib_file?(relative)
      return false unless relative.start_with?("lib/")

      relative.include?("sandboxed_tools") ||
        relative.include?("patch_support") ||
        relative.end_with?("ollama_agent/agent.rb") ||
        relative.end_with?("ollama_agent/tools_schema.rb")
    end

    def critical_path?(relative)
      return true if relative.match?(/\A(Gemfile|Gemfile\.lock)\z/)
      return true if relative.end_with?(".gemspec")
      return true if relative == "lib/ollama_agent/version.rb"
      return true if relative.start_with?("exe/")

      false
    end
  end
end

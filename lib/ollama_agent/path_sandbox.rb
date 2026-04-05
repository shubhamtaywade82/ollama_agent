# frozen_string_literal: true

require "pathname"

module OllamaAgent
  # Resolves paths under a project root using File.realpath so symlinks cannot escape the sandbox.
  module PathSandbox
    module_function

    # @param root_abs [String] File.expand_path of the project root (may be a symlink path)
    # @param root_real [String] File.realpath(root_abs) when the root exists
    # @param user_path [String] relative or absolute path from tool args
    def allowed?(root_abs, root_real, user_path)
      return false if user_path.nil? || user_path.to_s.strip.empty?

      expanded = Pathname(user_path.to_s).expand_path(root_abs).cleanpath.to_s
      return false unless lexically_under_root_abs?(expanded, root_abs)

      candidate_under_root?(expanded, root_real, root_abs)
    end

    def lexically_under_root_abs?(expanded_abs, root_abs)
      expanded_abs == root_abs || expanded_abs.start_with?(root_abs + File::SEPARATOR)
    end

    def candidate_under_root?(expanded_abs, root_real, root_abs)
      path_real = File.realpath(expanded_abs)
      under_root_real?(path_real, root_real)
    rescue Errno::ENOENT
      nonexistent_path_allowed_under_root?(expanded_abs, root_real, root_abs)
    rescue Errno::ELOOP, Errno::EACCES
      false
    end

    def under_root_real?(path_real, root_real)
      path_real == root_real || path_real.start_with?(root_real + File::SEPARATOR)
    end

    # rubocop:disable Metrics/MethodLength -- parent walk for missing path segments
    def nonexistent_path_allowed_under_root?(expanded_abs, root_real, root_abs)
      parent = expanded_abs
      loop do
        next_parent = File.dirname(parent)
        break if next_parent == parent

        parent = next_parent
        begin
          pr = File.realpath(parent)
          return false unless under_root_real?(pr, root_real)

          return lexically_under_root_abs?(expanded_abs, root_abs)
        rescue Errno::ENOENT
          next
        rescue Errno::ELOOP, Errno::EACCES
          return false
        end
      end
      false
    end
    # rubocop:enable Metrics/MethodLength
  end
end

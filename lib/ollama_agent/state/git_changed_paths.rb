# frozen_string_literal: true

module OllamaAgent
  module State
    # Lists paths from +git status --porcelain+ (no shell interpolation).
    module GitChangedPaths
      module_function

      def list(workspace_root)
        git_dir = File.join(workspace_root, ".git")
        return [] unless File.directory?(git_dir)

        out = IO.popen(["git", "-C", workspace_root, "status", "--porcelain"], &:read)
        out.to_s.split("\n").filter_map do |line|
          next if line.strip.empty?

          line[3..]&.strip
        end.compact.uniq
      end
    end
  end
end

# frozen_string_literal: true

require "find"
require "pathname"

module OllamaAgent
  # Enumerates files under the sandbox root (skips .git).
  module RepoList
    MAX_LIST_FILES = 500

    private

    def list_files(directory, max_entries)
      cap = clamp_list_limit(max_entries)
      dir = directory.to_s.empty? ? "." : directory
      return disallowed_path_message(dir) unless path_allowed?(dir)

      base = resolve_path(dir)
      return "Not a directory: #{dir}" unless File.directory?(base)

      paths = collect_relative_paths(base, cap)
      return "(no files listed)" if paths.empty?

      paths.sort.join("\n")
    end

    def collect_relative_paths(base, cap)
      paths = []
      Find.find(base) do |path|
        if git_directory?(path)
          Find.prune
        elsif File.file?(path)
          paths << Pathname(path).relative_path_from(Pathname(base)).to_s
          break if paths.size >= cap
        end
      end
      paths
    end

    def git_directory?(path)
      File.directory?(path) && File.basename(path) == ".git"
    end

    def clamp_list_limit(value)
      n = value.to_i
      n = 100 if n < 1
      [n, MAX_LIST_FILES].min
    end
  end
end

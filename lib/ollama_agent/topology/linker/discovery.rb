# frozen_string_literal: true

require "find"

module OllamaAgent
  module Topology
    class Linker
      # Collects Ruby sources under project roots while skipping bulky / vendored trees.
      class Discovery
        EXCLUDED_DIR_NAMES = %w[node_modules vendor/bundle tmp log .git].freeze

        def self.find_files(roots:, extensions: %w[.rb])
          expanded = Array(roots).map { |r| File.expand_path(r.to_s) }
          expanded.flat_map { |root| files_under_root(root, extensions) }.uniq.sort
        end

        def self.files_under_root(root, extensions)
          return [] unless File.directory?(root)

          found = []
          Find.find(root) do |path|
            if File.directory?(path)
              Find.prune if EXCLUDED_DIR_NAMES.include?(File.basename(path))
              next
            end
            found << File.expand_path(path) if extensions.any? { |ext| path.end_with?(ext) }
          end
          found
        end
      end
    end
  end
end

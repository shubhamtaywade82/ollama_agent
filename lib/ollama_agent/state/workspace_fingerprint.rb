# frozen_string_literal: true

require "digest"
require_relative "tree_digest"

module OllamaAgent
  module State
    # Deterministic workspace fingerprint computed from relative path and bytes.
    class WorkspaceFingerprint
      # @param ignore_under [String, nil] absolute path; files under this directory are skipped (e.g. kernel metadata)
      def initialize(root:, ignore_under: nil)
        @root = File.expand_path(root)
        @ignore_under = ignore_under ? File.expand_path(ignore_under) : nil
      end

      def compute
        digest = Digest::SHA256.new
        each_file do |relative_path, content|
          TreeDigest.append_entry(digest, relative_path, content)
        end
        digest.hexdigest
      end

      private

      def each_file
        file_paths.each do |absolute_path|
          next if ignored_path?(absolute_path)

          relative_path = absolute_path.delete_prefix("#{@root}/")
          yield relative_path, File.read(absolute_path)
        end
      end

      def ignored_path?(absolute_path)
        return false unless @ignore_under

        absolute_path == @ignore_under || absolute_path.start_with?("#{@ignore_under}/")
      end

      def file_paths
        Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH)
           .select { |path| File.file?(path) }
           .sort
      end
    end
  end
end

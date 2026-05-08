# frozen_string_literal: true

require "digest"
require_relative "tree_digest"

module OllamaAgent
  module State
    # Deterministic workspace fingerprint computed from relative path and bytes.
    class WorkspaceFingerprint
      def initialize(root:)
        @root = root
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
          relative_path = absolute_path.delete_prefix("#{@root}/")
          yield relative_path, File.read(absolute_path)
        end
      end

      def file_paths
        Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH)
           .select { |path| File.file?(path) }
           .sort
      end
    end
  end
end

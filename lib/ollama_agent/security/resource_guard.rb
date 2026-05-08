# frozen_string_literal: true

require "pathname"

module OllamaAgent
  module Security
    # Ensures candidate paths remain within the configured workspace root.
    class ResourceGuard
      def initialize(root:)
        @root = Pathname.new(root).realpath
      end

      def allow?(candidate_path)
        return false if candidate_path.to_s.empty?
        return false if raw_path_has_dot_dot?(candidate_path)

        expanded = expand_candidate(candidate_path)
        relative = expanded.relative_path_from(@root)
        return false if relative.each_filename.to_a.include?("..")

        segments_remain_under_root?(relative)
      rescue ArgumentError, Errno::ENOENT, Errno::ELOOP, Errno::EACCES
        false
      end

      private

      def segments_remain_under_root?(relative)
        walk = @root
        relative.each_filename do |segment|
          walk += segment
          next unless walk.exist?
          return false unless under_root?(walk.realpath)
        end
        true
      end

      def raw_path_has_dot_dot?(candidate_path)
        Pathname.new(candidate_path).each_filename.to_a.include?("..")
      end

      def expand_candidate(candidate_path)
        pn = Pathname.new(candidate_path)
        base = pn.absolute? ? pn : @root.join(pn)
        base.expand_path.cleanpath
      end

      def under_root?(path)
        s = path.to_s
        root_s = @root.to_s
        s == root_s || s.start_with?("#{root_s}#{File::SEPARATOR}")
      end
    end
  end
end

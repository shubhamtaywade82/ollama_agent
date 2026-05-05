# frozen_string_literal: true

module OllamaAgent
  module Indexing
    # Parses and summarizes unified diffs.
    # Provides human-readable change summaries and statistics without
    # needing the full file contents.
    class DiffSummarizer
      FileDiff = Data.define(:path, :additions, :deletions, :hunks, :is_new, :is_deleted, :is_rename)

      # Parse a unified diff string and return structured FileDiff objects.
      # @param diff [String] unified diff content
      # @return [Array<FileDiff>]
      def self.parse(diff)
        new.parse(diff)
      end

      # Return a short human-readable summary of a diff.
      # @param diff [String]
      # @return [String]
      def self.summarize(diff)
        new.summarize(diff)
      end

      def parse(diff)
        return [] if diff.nil? || diff.strip.empty?

        file_diffs = []
        current    = nil

        diff.each_line do |line|
          line = line.rstrip

          if line.start_with?("diff --git ")
            file_diffs << current if current
            current = new_file_diff(line)

          elsif line.start_with?("new file mode")
            current[:is_new] = true if current

          elsif line.start_with?("deleted file mode")
            current[:is_deleted] = true if current

          elsif line.start_with?("rename to ")
            current[:is_rename] = true if current

          elsif line.start_with?("--- ") || line.start_with?("+++ ")
            next # skip --- +++ headers

          elsif line.start_with?("@@")
            current[:hunks] += 1 if current

          elsif line.start_with?("+") && !line.start_with?("+++")
            current[:additions] += 1 if current

          elsif line.start_with?("-") && !line.start_with?("---")
            current[:deletions] += 1 if current
          end
        end

        file_diffs << current if current
        file_diffs.compact.map { |d| build_entry(d) }
      end

      # Human-readable multi-line summary.
      def summarize(diff)
        parsed = parse(diff)
        return "Empty diff" if parsed.empty?

        total_add = parsed.sum(&:additions)
        total_del = parsed.sum(&:deletions)
        header    = "#{parsed.size} file(s) changed: +#{total_add} -#{total_del}"

        lines = [header]
        parsed.each do |fd|
          tag = if fd.is_new then "[new]"
                elsif fd.is_deleted then "[deleted]"
                elsif fd.is_rename  then "[renamed]"
                else                     ""
                end

          lines << "  #{fd.path} #{tag} +#{fd.additions} -#{fd.deletions}"
        end

        lines.join("\n")
      end

      # Brief one-liner for embedding in prompts.
      def one_liner(diff)
        parsed = parse(diff)
        return "empty diff" if parsed.empty?

        paths   = parsed.map(&:path).first(3).join(", ")
        suffix  = parsed.size > 3 ? " (+#{parsed.size - 3} more)" : ""
        total_a = parsed.sum(&:additions)
        total_d = parsed.sum(&:deletions)

        "#{paths}#{suffix} [+#{total_a}/-#{total_d}]"
      end

      private

      def new_file_diff(header_line)
        # "diff --git a/path/to/file b/path/to/file"
        match = header_line.match(%r{diff --git a/(.+) b/})
        path  = match ? match[1] : header_line.split.last

        { path: path, additions: 0, deletions: 0, hunks: 0,
          is_new: false, is_deleted: false, is_rename: false }
      end

      def build_entry(d)
        FileDiff.new(
          path: d[:path],
          additions: d[:additions],
          deletions: d[:deletions],
          hunks: d[:hunks],
          is_new: d[:is_new],
          is_deleted: d[:is_deleted],
          is_rename: d[:is_rename]
        )
      end
    end
  end
end

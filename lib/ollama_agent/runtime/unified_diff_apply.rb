# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # Pure-Ruby application of a unified diff to a single file (no shell).
    # Supports typical git-style hunks; multiple hunks are applied bottom-up.
    module UnifiedDiffApply
      module_function

      Hunk = Struct.new(:old_start, :old_count, :body, keyword_init: true)

      def to_line_array(content)
        return [] if content.nil? || content.empty?

        content.each_line.map { |l| l.delete_suffix("\n") }
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- diff engine
      # @param old_content [String] current file bytes (UTF-8 or binary)
      # @param diff_text [String] unified diff (may include headers)
      # @return [:ok, String] or [:error, String]
      def apply(old_content, diff_text)
        hunks = parse_hunks(diff_text.to_s)
        return [:error, "no hunk in patch"] if hunks.empty?

        lines = to_line_array(old_content)
        had_trailing_nl = old_content.end_with?("\n")
        sorted = hunks.sort_by { |hunk| -hunk.old_start }
        sorted.each do |hunk|
          lines = apply_hunk(lines, hunk)
          return [:error, "patch did not apply cleanly"] unless lines
        end

        out = lines.join("\n")
        out += "\n" if had_trailing_nl || !old_content.empty?
        [:ok, out]
      end

      def parse_hunks(diff_text)
        raw = diff_text.lines.map(&:chomp)
        hunks = []
        i = 0
        while i < raw.length
          line = raw[i]
          if line.start_with?("@@")
            m = line.match(/@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/)
            unless m
              i += 1
              next
            end
            old_start = m[1].to_i
            old_count = m[2] ? m[2].to_i : 1
            i += 1
            body = []
            while i < raw.length && !raw[i].start_with?("@@") && !raw[i].start_with?("diff --git")
              l = raw[i]
              i += 1
              next if l.empty?

              first = l[0]
              next if first == "\\"

              body << l if " +-".include?(first)
            end
            hunks << Hunk.new(old_start: old_start, old_count: old_count, body: body)
          else
            i += 1
          end
        end
        hunks
      end

      def apply_hunk(lines, hunk)
        work = lines.dup
        idx = hunk.old_start - 1
        return nil if idx.negative?

        hunk.body.each do |raw|
          op = raw[0]
          text = raw[1..]
          case op
          when " "
            return nil unless work[idx] == text

            idx += 1
          when "-"
            return nil unless work[idx] == text

            work.delete_at(idx)
          when "+"
            work.insert(idx, text)
            idx += 1
          else
            return nil
          end
        end
        work
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    end
  end
end

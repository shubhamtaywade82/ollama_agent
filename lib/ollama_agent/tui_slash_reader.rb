# frozen_string_literal: true

require "tty-reader"

module OllamaAgent
  # Longest shared prefix for tab completion (readline-style).
  module SlashCompletion
    module_function

    # rubocop:disable Metrics/CyclomaticComplexity -- straightforward index scan
    def longest_common_prefix(strings)
      arr = Array(strings).map(&:to_s).reject(&:empty?)
      return "" if arr.empty?

      first = arr.first
      i = 0
      i += 1 while i < first.length && arr.all? { |s| i < s.length && s[i] == first[i] }
      first[0, i]
    end
    # rubocop:enable Metrics/CyclomaticComplexity
  end

  # Extends {TTY::Reader} so Tab completes lines that start with +/+ against a fixed candidate list.
  #
  # Line editing and history match tty-reader +read_line+; only the Tab code path differs.
  # Implementation synced from tty-reader 0.9.0 (+lib/tty/reader.rb+).
  # rubocop:disable Metrics/PerceivedComplexity, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Style/StringConcatenation, Metrics/BlockNesting
  class TuiSlashReader < TTY::Reader
    def initialize(completion_candidates:, **)
      super(**)
      @completion_candidates = Array(completion_candidates).uniq.sort.freeze
    end

    def read_line(prompt = "", value: "", echo: true, raw: true, nonblock: false)
      line = TTY::Reader::Line.new(value, prompt: prompt)
      screen_width = TTY::Screen.width
      buffer = ""

      output.print(line)

      while (codes = get_codes(echo: echo, raw: raw, nonblock: nonblock)) &&
            (code = codes[0])
        char = codes.pack("U*")

        if EXIT_KEYS.include?(console.keys[char])
          trigger_key_event(char, line: line.to_s)
          break
        end

        clear_display(line, screen_width) if raw && echo

        if console.keys[char] == :backspace || code == BACKSPACE
          unless line.start?
            line.left
            line.delete
          end
        elsif console.keys[char] == :delete || code == DELETE
          line.delete
        elsif console.keys[char].to_s =~ /ctrl_/
          # skip
        elsif console.keys[char] == :up
          line.replace(mutable_copy(history_previous)) if history_previous?
        elsif console.keys[char] == :down
          line.replace(mutable_copy(history_next? ? history_next : buffer)) if track_history?
        elsif console.keys[char] == :left
          line.left
        elsif console.keys[char] == :right
          line.right
        elsif console.keys[char] == :home
          line.move_to_start
        elsif console.keys[char] == :end
          line.move_to_end
        elsif console.keys[char] == :tab
          buffer = apply_slash_tab!(line, char)
        else
          if raw && code == CARRIAGE_RETURN
            char = "\n"
            line.move_to_end
          end
          line.insert(char)
          buffer = line.text
        end

        if (console.keys[char] == :backspace || code == BACKSPACE) && echo
          if raw
            output.print("\e[1X") unless line.start?
          else
            output.print(" " + (line.start? ? "" : "\b"))
          end
        end

        trigger_key_event(char, line: line.to_s)

        if raw && echo
          output.print(line.to_s)
          if char == "\n"
            line.move_to_start
          elsif !line.end?
            output.print(cursor.backward(line.text_size - line.cursor))
          end
        end

        next unless [CARRIAGE_RETURN, NEWLINE].include?(code)

        buffer = ""
        output.puts unless echo
        break
      end

      add_to_history(line.text.rstrip) if track_history? && echo

      line.text
    end

    private

    # {TTY::Reader::Line#replace} keeps the same string object; frozen literals (e.g. tab candidates) must be copied.
    def mutable_copy(str)
      str.to_s.dup
    end

    def apply_slash_tab!(line, char)
      text = line.text
      unless text.start_with?("/")
        line.insert(char)
        return line.text
      end

      matches = @completion_candidates.select { |c| c.start_with?(text) }
      return line.text if matches.empty?

      if matches.size == 1
        line.replace(mutable_copy(matches.first))
      else
        prefix = SlashCompletion.longest_common_prefix(matches)
        if prefix.length > text.length
          line.replace(mutable_copy(prefix))
        else
          output.puts
          matches.each { |m| output.puts "  #{m}" }
        end
      end
      line.text
    end
  end
  # rubocop:enable Metrics/PerceivedComplexity, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Style/StringConcatenation, Metrics/BlockNesting
end

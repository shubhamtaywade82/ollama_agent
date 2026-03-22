# frozen_string_literal: true

module OllamaAgent
  module RubyIndex
    # Turns index rows into capped plain-text lines for tool responses.
    module Formatter
      module_function

      DEFAULT_MAX_LINES = 200
      DEFAULT_MAX_CHARS = 60_000

      def format_constants(records, max_lines: nil, max_chars: nil)
        return "(no matches)\n" if records.empty?

        max_lines = (max_lines || env_int("OLLAMA_AGENT_RUBY_INDEX_MAX_LINES") || DEFAULT_MAX_LINES).to_i
        max_chars = (max_chars || env_int("OLLAMA_AGENT_RUBY_INDEX_MAX_CHARS") || DEFAULT_MAX_CHARS).to_i
        lines = records.map { |r| format_constant_row(r) }
        cap(lines, max_lines, max_chars)
      end

      def format_methods(records, max_lines: nil, max_chars: nil)
        return "(no matches)\n" if records.empty?

        max_lines = (max_lines || env_int("OLLAMA_AGENT_RUBY_INDEX_MAX_LINES") || DEFAULT_MAX_LINES).to_i
        max_chars = (max_chars || env_int("OLLAMA_AGENT_RUBY_INDEX_MAX_CHARS") || DEFAULT_MAX_CHARS).to_i
        lines = records.map { |r| format_method_row(r) }
        cap(lines, max_lines, max_chars)
      end

      def env_int(name)
        v = ENV.fetch(name, nil)
        return nil if v.nil? || v.empty?

        Integer(v)
      rescue ArgumentError
        nil
      end

      def format_constant_row(row)
        kind = row[:kind]
        "#{kind} #{row[:name]}  #{row[:path]}:#{row[:start_line]}-#{row[:end_line]}"
      end

      def format_method_row(row)
        sig = row[:singleton] ? "singleton" : "instance"
        ns = row[:namespace].to_s
        ns_part = ns.empty? ? "(toplevel)" : ns
        "method #{row[:name]}  #{sig}  #{ns_part}  #{row[:path]}:#{row[:start_line]}-#{row[:end_line]}"
      end

      def cap(lines, max_lines, max_chars)
        out = +""
        lines.first(max_lines).each do |line|
          break if out.bytesize + line.bytesize + 1 > max_chars

          out << line
          out << "\n"
        end
        truncated = lines.size > max_lines || out.bytesize >= max_chars
        out << "(truncated)\n" if truncated
        out
      end
    end
  end
end

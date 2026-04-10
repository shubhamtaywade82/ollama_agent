# frozen_string_literal: true

require_relative "../search_backend"

module OllamaAgent
  module SandboxedTools
    # ripgrep/grep-backed search_code (text mode).
    module SearchText
      private

      def execute_search_code(args)
        pattern = tool_arg(args, "pattern").to_s
        mode = (tool_arg(args, "mode") || "text").to_s.downcase

        return missing_tool_argument("search_code", "pattern") if blank_tool_value?(pattern)

        return search_code_ruby(pattern, mode) if ruby_search_mode?(mode)

        search_code(pattern, tool_arg(args, "directory") || ".")
      end

      def search_code(pattern, directory)
        dir = directory.to_s.empty? ? "." : directory
        return disallowed_path_message(dir) unless path_allowed?(dir)

        return search_code_no_backends_message unless rg_available? || grep_available?

        return search_with_ripgrep(pattern, dir) if rg_available?

        search_with_grep!(pattern, dir)
      end

      def search_with_ripgrep(pattern, directory)
        bin = SearchBackend.rg_executable
        stdout, = Open3.capture2(bin, "-n", "--", pattern, resolve_path(directory))
        stdout.to_s
      end

      def search_with_grep!(pattern, directory)
        bin = SearchBackend.grep_executable
        stdout, = Open3.capture2(bin, "-rn", "--", pattern, resolve_path(directory))
        stdout.to_s
      end

      def search_code_no_backends_message
        <<~MSG.strip
          Error: ollama_agent: no text search backend available. Install ripgrep (`rg`) or GNU grep on PATH.
        MSG
      end

      def rg_available?
        !SearchBackend.rg_executable.nil?
      end

      def grep_available?
        !SearchBackend.grep_executable.nil?
      end
    end
  end
end

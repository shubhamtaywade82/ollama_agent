# frozen_string_literal: true

module OllamaAgent
  module SandboxedTools
    # read_file / write_file and line-range helpers.
    module FileReadWrite
      private

      def execute_read_file(args)
        path = tool_arg(args, "path")
        return missing_tool_argument("read_file", "path") if blank_tool_value?(path)

        read_file(
          path,
          start_line: tool_arg(args, "start_line"),
          end_line: tool_arg(args, "end_line")
        )
      end

      def execute_write_file_tool(args)
        path = tool_arg(args, "path")
        content = tool_arg(args, "content")
        return missing_tool_argument("write_file", "path") if blank_tool_value?(path)
        return missing_tool_argument("write_file", "content") if content.nil?

        write_file(path, content)
      end

      def write_file(path, content)
        return disallowed_path_message(path) unless path_allowed?(path)
        return "write_file is disabled in read-only mode." if @read_only

        return "Cancelled by user" if @confirm_patches && !user_prompt.confirm_write_file(path, content.to_s[0, 2000])

        abs = resolve_path(path)
        FileUtils.mkdir_p(File.dirname(abs))
        File.write(abs, content.to_s, encoding: Encoding::UTF_8)
        "Written: #{path}"
      rescue Errno::EACCES => e
        "Error writing file: #{e.message}"
      end

      def read_file(path, start_line: nil, end_line: nil)
        return disallowed_path_message(path) unless path_allowed?(path)

        abs = resolve_path(path)
        return read_file_lines(abs, start_line, end_line) if start_line || end_line

        return read_file_too_large(abs) if File.size(abs) > max_read_file_bytes

        File.read(abs)
      rescue Errno::ENOENT => e
        "Error reading file: #{e.message}"
      end

      def read_file_too_large(abs)
        n = max_read_file_bytes
        "Error reading file: ollama_agent: file too large for full read (max #{n} bytes); use read_file with " \
          "start_line and end_line, or raise OLLAMA_AGENT_MAX_READ_FILE_BYTES. Path: #{abs}"
      end

      def max_read_file_bytes
        EnvConfig.fetch_int(
          "OLLAMA_AGENT_MAX_READ_FILE_BYTES",
          DEFAULT_MAX_READ_FILE_BYTES,
          strict: EnvConfig.strict_env?
        )
      end

      def read_file_lines(abs, start_line, end_line)
        start_i = read_line_start_index(start_line)
        end_i = read_line_end_index(end_line)
        return "" if end_i && start_i > end_i

        accumulate_file_lines(abs, start_i, end_i)
      rescue Errno::ENOENT => e
        "Error reading file: #{e.message}"
      end

      def read_line_start_index(start_line)
        [integer_or(start_line, 1), 1].max
      end

      def read_line_end_index(end_line)
        end_line.nil? ? nil : integer_or(end_line, 1)
      end

      def accumulate_file_lines(abs, start_i, end_i)
        buf = +""
        File.foreach(abs).with_index(1) do |line, lineno|
          next if lineno < start_i
          break if end_i && lineno > end_i

          buf << line
        end
        buf
      end
    end
  end
end

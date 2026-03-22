# frozen_string_literal: true

require "open3"
require "pathname"

require_relative "console"
require_relative "diff_path_validator"
require_relative "patch_support"
require_relative "repo_list"
require_relative "ruby_index_tool_support"
require_relative "tool_arguments"

module OllamaAgent
  # File read, search, and patch application constrained to a project root.
  # rubocop:disable Metrics/ModuleLength -- tool dispatch, I/O, and Ruby index support
  module SandboxedTools
    include PatchSupport
    include RepoList
    include RubyIndexToolSupport
    include ToolArguments

    private

    def execute_tool(name, args)
      args = coerce_tool_arguments(args)
      case name
      when "read_file" then execute_read_file(args)
      when "search_code" then execute_search_code(args)
      when "list_files" then execute_list_files(args)
      when "edit_file" then execute_edit_file_tool(args)
      else "Unknown tool: #{name}"
      end
    end

    def execute_read_file(args)
      path = tool_arg(args, "path")
      return missing_tool_argument("read_file", "path") if blank_tool_value?(path)

      read_file(
        path,
        start_line: tool_arg(args, "start_line"),
        end_line: tool_arg(args, "end_line")
      )
    end

    def execute_search_code(args)
      pattern = tool_arg(args, "pattern").to_s
      mode = (tool_arg(args, "mode") || "text").to_s.downcase

      return search_code_ruby(pattern, mode) if ruby_search_mode?(mode)

      return missing_tool_argument("search_code", "pattern") if blank_tool_value?(pattern)

      search_code(pattern, tool_arg(args, "directory") || ".")
    end

    def execute_list_files(args)
      directory = tool_arg(args, "directory") || "."
      list_files(directory, tool_arg(args, "max_entries"))
    end

    def execute_edit_file_tool(args)
      path = tool_arg(args, "path")
      diff = tool_arg(args, "diff")
      return missing_tool_argument("edit_file", "path") if blank_tool_value?(path)
      return missing_tool_argument("edit_file", "diff") if diff.nil?

      edit_file(path, diff)
    end

    def read_file(path, start_line: nil, end_line: nil)
      return disallowed_path_message(path) unless path_allowed?(path)

      abs = resolve_path(path)
      return read_file_lines(abs, start_line, end_line) if start_line || end_line

      File.read(abs)
    rescue Errno::ENOENT => e
      "Error reading file: #{e.message}"
    end

    def read_file_lines(abs, start_line, end_line)
      lines = File.readlines(abs)
      return "" if lines.empty?

      total = lines.size
      end_i = integer_or(end_line, total).clamp(1, total)
      start_i = integer_or(start_line, 1).clamp(1, total)
      return "" if start_i > end_i

      slice = lines[(start_i - 1)..(end_i - 1)]
      slice ? slice.join : ""
    end

    def integer_or(value, default)
      return default if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      default
    end

    def search_code(pattern, directory)
      dir = directory.to_s.empty? ? "." : directory
      return disallowed_path_message(dir) unless path_allowed?(dir)

      search_with_ripgrep(pattern, dir) || search_with_grep(pattern, dir)
    end

    def search_with_ripgrep(pattern, directory)
      return nil unless rg_available?

      stdout, = Open3.capture2("rg", "-n", "--", pattern, resolve_path(directory))
      stdout.to_s
    end

    def search_with_grep(pattern, directory)
      stdout, = Open3.capture2("grep", "-rn", "--", pattern, resolve_path(directory))
      stdout.to_s
    end

    def rg_available?
      system("which", "rg", out: File::NULL, err: File::NULL)
    end

    def edit_file(path, diff)
      return disallowed_path_message(path) unless path_allowed?(path)

      diff = DiffPathValidator.normalize_diff(diff)

      validation = validate_edit_diff(path, diff)
      return validation if validation

      return "Cancelled by user" if @confirm_patches && !user_confirms_patch?(path, diff)

      apply_patch(diff)
    end

    def validate_edit_diff(path, diff)
      mismatch = DiffPathValidator.call(diff, @root, path)
      return log_tool_message(mismatch) if mismatch

      dry = patch_dry_run(diff)
      return log_tool_message(dry) if dry

      nil
    end

    def log_tool_message(message)
      warn "ollama_agent: #{message}" if ENV["OLLAMA_AGENT_DEBUG"] == "1"

      message
    end

    def tool_arg(args, key)
      args[key] || args[key.to_sym]
    end

    def user_confirms_patch?(path, diff)
      puts Console.patch_title("Proposed diff for #{path}:")
      puts diff
      print Console.apply_prompt("Apply? (y/n) ")
      $stdin.gets.to_s.chomp.casecmp("y").zero?
    end

    def resolve_path(path)
      Pathname(path.to_s).expand_path(@root).to_s
    end

    def path_allowed?(path)
      return false if blank_tool_value?(path)

      resolved = resolve_path(path)
      root = File.expand_path(@root)
      resolved == root || resolved.start_with?(root + File::SEPARATOR)
    end

    def disallowed_path_message(path)
      "Path must stay under project root #{@root}: #{path}"
    end
  end
  # rubocop:enable Metrics/ModuleLength
end

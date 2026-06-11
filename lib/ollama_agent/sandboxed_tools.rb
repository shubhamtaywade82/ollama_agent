# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"

require_relative "console"
require_relative "path_sandbox"
require_relative "user_prompt"
require_relative "env_config"
require_relative "diff_path_validator"
require_relative "patch_risk"
require_relative "patch_support"
require_relative "repo_list"
require_relative "ruby_index_tool_support"
require_relative "tool_arguments"
require_relative "external_agents"
require_relative "sandboxed_tools/file_read_write"
require_relative "sandboxed_tools/search_text"
require_relative "sandboxed_tools/delegate_external"

module OllamaAgent
  module SandboxedTools
    DEFAULT_MAX_READ_FILE_BYTES = 2_097_152

    def execute_tool(name, args)
      context = {
        root: @root,
        read_only: @config.runtime.read_only,
        memory_manager: @memory_manager,
        shell_call_count: @shell_call_count || 0
      }
      @toolbox.send(:execute, name, args, context: context)
    end

    # Forward private tool helpers so agent.send(:read_file, ...) still works.
    # These are called by tests and live in Toolbox via the included sub-modules.
    private

    def read_file(path, start_line: nil, end_line: nil)
      @toolbox.send(:read_file, path, start_line: start_line, end_line: end_line)
    end

    def edit_file(path, diff)
      @toolbox.send(:edit_file, path, diff)
    end

    def list_files(directory, max_entries, max_depth: nil)
      @toolbox.send(:list_files, directory, max_entries, max_depth: max_depth)
    end

    def search_code(pattern, directory)
      @toolbox.send(:search_code, pattern, directory)
    end

    def search_with_ripgrep(pattern, directory)
      @toolbox.send(:search_with_ripgrep, pattern, directory)
    end

    def search_with_grep!(pattern, directory)
      @toolbox.send(:search_with_grep!, pattern, directory)
    end

    def patch_available?
      @toolbox.send(:patch_available?)
    end

    def patch_dry_run(diff)
      @toolbox.send(:patch_dry_run, diff)
    end

    def apply_patch(diff)
      @toolbox.send(:apply_patch, diff)
    end

    def execute_read_file(args)
      @toolbox.send(:execute_read_file, args)
    end

    def execute_write_file_tool(args)
      @toolbox.send(:execute_write_file_tool, args)
    end

    def execute_edit_file_tool(args)
      @toolbox.send(:execute_edit_file_tool, args)
    end

    def execute_search_code(args)
      @toolbox.send(:execute_search_code, args)
    end

    def execute_list_files(args)
      @toolbox.send(:execute_list_files, args)
    end

    def execute_list_directory_contents(args)
      @toolbox.send(:execute_list_directory_contents, args)
    end

    def execute_calculate(args)
      @toolbox.send(:execute_calculate, args)
    end

    def execute_list_external_agents(args)
      @toolbox.send(:execute_list_external_agents, args)
    end

    def execute_delegate_to_agent_tool(args)
      @toolbox.send(:execute_delegate_to_agent_tool, args)
    end

    def integer_or(value, default)
      @toolbox.send(:integer_or, value, default)
    end

    def disallowed_path_message(path)
      @toolbox.send(:disallowed_path_message, path)
    end

    def path_allowed?(path)
      @toolbox.send(:path_allowed?, path)
    end

    def blank_tool_value?(value)
      @toolbox.send(:blank_tool_value?, value)
    end

    def tool_arg(args, key)
      @toolbox.send(:tool_arg, args, key)
    end

    def missing_tool_argument(tool, arg_name)
      @toolbox.send(:missing_tool_argument, tool, arg_name)
    end

    def coerce_tool_arguments(args)
      @toolbox.send(:coerce_tool_arguments, args)
    end

    def user_confirms_patch?(path, diff)
      @toolbox.send(:user_confirms_patch?, path, diff)
    end

    def user_prompt
      @toolbox.send(:user_prompt)
    end

    def resolve_path(path)
      @toolbox.send(:resolve_path, path)
    end

    def sandbox_root_abs
      @toolbox.send(:sandbox_root_abs)
    end

    def sandbox_root_real
      @toolbox.send(:sandbox_root_real)
    end

    def log_tool_message(message)
      @toolbox.send(:log_tool_message, message)
    end

    def patch_confirmation_needed?(path, diff)
      @toolbox.send(:patch_confirmation_needed?, path, diff)
    end

    def validate_edit_diff(path, diff)
      @toolbox.send(:validate_edit_diff, path, diff)
    end

    def write_file(path, content)
      @toolbox.send(:write_file, path, content)
    end

    def max_read_file_bytes
      @toolbox.send(:max_read_file_bytes)
    end

    def read_file_too_large(abs)
      @toolbox.send(:read_file_too_large, abs)
    end

    def accumulate_file_lines(abs, start_i, end_i)
      @toolbox.send(:accumulate_file_lines, abs, start_i, end_i)
    end

    def read_file_lines(abs, start_line, end_line)
      @toolbox.send(:read_file_lines, abs, start_line, end_line)
    end

    def read_line_start_index(start_line)
      @toolbox.send(:read_line_start_index, start_line)
    end

    def read_line_end_index(end_line)
      @toolbox.send(:read_line_end_index, end_line)
    end

    def search_timeout_seconds
      @toolbox.send(:search_timeout_seconds)
    end

    def rg_available?
      @toolbox.send(:rg_available?)
    end

    def grep_available?
      @toolbox.send(:grep_available?)
    end

    def search_code_no_backends_message
      @toolbox.send(:search_code_no_backends_message)
    end

    def capture_search_output(&)
      @toolbox.send(:capture_search_output, &)
    end

    def ruby_search_mode?(mode)
      @toolbox.send(:ruby_search_mode?, mode)
    end

    def search_code_ruby(pattern, mode)
      @toolbox.send(:search_code_ruby, pattern, mode)
    end

    def ruby_index
      @toolbox.send(:ruby_index)
    end

    def external_registry
      @toolbox.send(:external_registry)
    end

    def user_confirms_delegate?(agent_id, task)
      @toolbox.send(:user_confirms_delegate?, agent_id, task)
    end
  end
end
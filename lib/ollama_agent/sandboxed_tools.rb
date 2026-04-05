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
  # File read, search, and patch application constrained to a project root.
  module SandboxedTools
    DEFAULT_MAX_READ_FILE_BYTES = 2_097_152

    include FileReadWrite
    include SearchText
    include DelegateExternal
    include PatchSupport
    include RepoList
    include RubyIndexToolSupport
    include ToolArguments

    private

    # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
    def execute_tool(name, args)
      args = coerce_tool_arguments(args)

      if Tools::Registry.custom_tool?(name)
        return Tools::Registry.execute_custom(name, args, root: @root, read_only: @read_only)
      end

      case name
      when "read_file"            then execute_read_file(args)
      when "search_code"          then execute_search_code(args)
      when "list_files"           then execute_list_files(args)
      when "edit_file"            then execute_edit_file_tool(args)
      when "write_file"           then execute_write_file_tool(args)
      when "list_external_agents" then execute_list_external_agents(args)
      when "delegate_to_agent"    then execute_delegate_to_agent_tool(args)
      else "Unknown tool: #{name}"
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity

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

    def integer_or(value, default)
      return default if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      default
    end

    def edit_file(path, diff)
      return disallowed_path_message(path) unless path_allowed?(path)
      return "edit_file is disabled in read-only mode." if @read_only

      diff = DiffPathValidator.normalize_diff(diff)

      validation = validate_edit_diff(path, diff)
      return validation if validation

      return "Rejected: diff matches a forbidden pattern (unsafe)." if PatchRisk.forbidden?(diff)

      return "Cancelled by user" if patch_confirmation_needed?(path, diff) && !user_confirms_patch?(path, diff)

      apply_patch(diff)
    end

    def patch_confirmation_needed?(path, diff)
      return false unless @confirm_patches
      return true unless @patch_policy

      @patch_policy.call(path, diff) == :require_confirmation
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
      user_prompt.confirm_patch(path, diff)
    end

    def resolve_path(path)
      Pathname(path.to_s).expand_path(sandbox_root_abs).to_s
    end

    def sandbox_root_abs
      @sandbox_root_abs ||= File.expand_path(@root)
    end

    def sandbox_root_real
      @sandbox_root_real ||= File.realpath(sandbox_root_abs)
    rescue Errno::ENOENT, Errno::ELOOP, Errno::EACCES
      sandbox_root_abs
    end

    def path_allowed?(path)
      return false if blank_tool_value?(path)

      PathSandbox.allowed?(sandbox_root_abs, sandbox_root_real, path)
    end

    def user_prompt
      @user_prompt ||= UserPrompt.new
    end

    def disallowed_path_message(path)
      "Path must stay under project root #{@root}: #{path}"
    end
  end
end

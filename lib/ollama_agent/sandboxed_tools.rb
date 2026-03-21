# frozen_string_literal: true

require "open3"
require "pathname"

module OllamaAgent
  # File read, search, and patch application constrained to a project root.
  module SandboxedTools
    private

    def execute_tool(name, args)
      case name
      when "read_file" then read_file(args["path"])
      when "search_code" then search_code(args["pattern"], args["directory"] || ".")
      when "edit_file" then edit_file(args["path"], args["diff"])
      else "Unknown tool: #{name}"
      end
    end

    def read_file(path)
      return disallowed_path_message(path) unless path_allowed?(path)

      File.read(resolve_path(path))
    rescue Errno::ENOENT => e
      "Error reading file: #{e.message}"
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

      return "Cancelled by user" if @confirm_patches && !user_confirms_patch?(path, diff)

      apply_patch(diff)
    end

    def user_confirms_patch?(path, diff)
      puts "Proposed diff for #{path}:"
      puts diff
      print "Apply? (y/n) "
      $stdin.gets.to_s.chomp.casecmp("y").zero?
    end

    def apply_patch(diff)
      output, status = Open3.capture2e(
        "patch", "-p1", "-f", "-d", @root,
        stdin_data: diff
      )

      return "Patch applied successfully." if status.success?

      "Patch application failed: #{output.strip}"
    end

    def resolve_path(path)
      Pathname(path).expand_path(@root).to_s
    end

    def path_allowed?(path)
      resolved = resolve_path(path)
      root = File.expand_path(@root)
      resolved == root || resolved.start_with?(root + File::SEPARATOR)
    end

    def disallowed_path_message(path)
      "Path must stay under project root #{@root}: #{path}"
    end
  end
end

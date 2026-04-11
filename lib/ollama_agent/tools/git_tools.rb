# frozen_string_literal: true

require "open3"
require_relative "base"

module OllamaAgent
  module Tools
    # Git status — read-only, no approval needed
    class GitStatus < Base
      tool_name        "git_status"
      tool_description "Show the working tree status (staged, unstaged, untracked files)"
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
        type: "object",
        properties: {
          short: { type: "boolean", description: "Use short format (default: false)" }
        },
        required: []
      })

      def call(args, context: {})
        root  = context[:root] || Dir.pwd
        short = args["short"] ? "--short" : "--porcelain=v1"
        git_run("git status #{short}", cwd: root)
      end
    end

    # Git diff — read-only
    class GitDiff < Base
      tool_name        "git_diff"
      tool_description "Show changes between commits, working tree, or index"
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
        type: "object",
        properties: {
          ref:    { type: "string", description: "Commit, branch, or tag to diff against (default: HEAD)" },
          cached: { type: "boolean", description: "Show staged changes (--cached)" },
          path:   { type: "string", description: "Limit diff to this path" }
        },
        required: []
      })

      MAX_DIFF_BYTES = 32_768

      def call(args, context: {})
        root   = context[:root] || Dir.pwd
        ref    = args["ref"]
        cached = args["cached"] ? "--cached" : ""
        path   = args["path"]

        cmd_parts = ["git diff", cached, ref, "--", path].compact.reject(&:empty?)
        output = git_run(cmd_parts.join(" "), cwd: root)
        output.byteslice(0, MAX_DIFF_BYTES).then { |o| output.bytesize > MAX_DIFF_BYTES ? "#{o}\n...[truncated]" : o }
      end
    end

    # Git log — read-only
    class GitLog < Base
      tool_name        "git_log"
      tool_description "Show commit history"
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
        type: "object",
        properties: {
          n:      { type: "integer", description: "Number of commits (default 10)", minimum: 1, maximum: 100 },
          oneline:{ type: "boolean", description: "One-line format" },
          author: { type: "string",  description: "Filter by author" },
          path:   { type: "string",  description: "Limit to commits touching this path" }
        },
        required: []
      })

      def call(args, context: {})
        root    = context[:root] || Dir.pwd
        n       = [args["n"]&.to_i || 10, 100].min
        format  = args["oneline"] ? "--oneline" : "--pretty=format:%h %s (%an, %ar)"
        author  = args["author"]  ? "--author=#{Shellwords.shellescape(args["author"])}" : ""
        path    = args["path"]

        cmd_parts = ["git log", "-n #{n}", format, author, "--", path].compact.reject(&:empty?)
        git_run(cmd_parts.join(" "), cwd: root)
      end
    end

    # Git commit — requires approval
    class GitCommit < Base
      tool_name        "git_commit"
      tool_description "Stage specified files and create a git commit"
      tool_risk        :medium
      tool_requires_approval true
      tool_schema({
        type: "object",
        properties: {
          message: { type: "string", description: "Commit message", minLength: 3 },
          files:   {
            type: "array",
            items: { type: "string" },
            description: "Files to stage (use ['.'] for all changed files — use carefully)"
          },
          all:     { type: "boolean", description: "Stage all tracked changes (-a flag)" }
        },
        required: ["message"]
      })

      def call(args, context: {})
        return "git_commit is disabled in read-only mode" if context[:read_only]

        root    = context[:root] || Dir.pwd
        message = args["message"].to_s.strip
        return "Error: commit message is required" if message.empty?

        files = Array(args["files"])
        all   = args["all"]

        # Stage files
        if all
          git_run("git add -u", cwd: root)
        elsif files.any?
          safe_files = files.map { |f| Shellwords.shellescape(f) }.join(" ")
          git_run("git add #{safe_files}", cwd: root)
        end

        git_run("git commit -m #{Shellwords.shellescape(message)}", cwd: root)
      end
    end

    # Git branch list — read-only
    class GitBranch < Base
      tool_name        "git_branch"
      tool_description "List branches or show current branch"
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
        type: "object",
        properties: {
          all:     { type: "boolean", description: "Include remote branches" },
          current: { type: "boolean", description: "Show current branch name only" }
        },
        required: []
      })

      def call(args, context: {})
        root = context[:root] || Dir.pwd

        if args["current"]
          git_run("git rev-parse --abbrev-ref HEAD", cwd: root)
        elsif args["all"]
          git_run("git branch -a", cwd: root)
        else
          git_run("git branch", cwd: root)
        end
      end
    end

    private

    def git_run(cmd, cwd:)
      stdout, stderr, status = Open3.capture3(cmd, chdir: cwd)
      out = stdout.strip
      err = stderr.strip
      result = [out, (err.empty? ? nil : "stderr: #{err}")].compact.join("\n")
      result.empty? ? "(no output)" : result
    rescue Errno::ENOENT
      "Error: git not found on PATH"
    end

    module_function :git_run
    public :git_run
  end
end

# frozen_string_literal: true

require "open3"
require "shellwords"
require_relative "base"

module OllamaAgent
  module Tools
    # Shared helper for git-* tools (instance-level `git_run`, not a module function).
    class GitBase < Base
      private

      def git_run(cmd, cwd:)
        stdout, stderr, _status = Open3.capture3(cmd, chdir: cwd)
        out = stdout.strip
        err = stderr.strip
        result = [out, (err.empty? ? nil : "stderr: #{err}")].compact.join("\n")
        result.empty? ? "(no output)" : result
      rescue Errno::ENOENT
        "Error: git not found on PATH"
      end
    end

    # Git status — read-only, no approval needed
    class GitStatus < GitBase
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
    class GitDiff < GitBase
      tool_name        "git_diff"
      tool_description "Show changes between commits, working tree, or index"
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      ref: { type: "string", description: "Commit, branch, or tag to diff against (default: HEAD)" },
                      cached: { type: "boolean", description: "Show staged changes (--cached)" },
                      path: { type: "string", description: "Limit diff to this path" }
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
    class GitLog < GitBase
      tool_name        "git_log"
      tool_description "Show commit history"
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      n: { type: "integer", description: "Number of commits (default 10)", minimum: 1, maximum: 100 },
                      oneline: { type: "boolean", description: "One-line format" },
                      author: { type: "string", description: "Filter by author" },
                      path: { type: "string", description: "Limit to commits touching this path" }
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
    class GitCommit < GitBase
      tool_name        "git_commit"
      tool_description "Stage specified files and create a git commit"
      tool_risk        :medium
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      message: { type: "string", description: "Commit message", minLength: 3 },
                      files: {
                        type: "array",
                        items: { type: "string" },
                        description: "Files to stage (use ['.'] for all changed files — use carefully)"
                      },
                      all: { type: "boolean", description: "Stage all tracked changes (-a flag)" }
                    },
                    required: ["message"]
                  })

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- staging branches + commit
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
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    end

    # Create and checkout a new git branch (not just list).
    class GitCreateBranch < GitBase
      tool_name        "create_branch"
      tool_description "Create and checkout a new feature branch. Agents should NEVER commit to main."
      tool_risk        :medium
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      name: { type: "string", description: "Branch name (alphanumeric, hyphens, underscores only)" },
                      base: { type: "string", description: "Base branch (default: main)" }
                    },
                    required: ["name"]
                  })

      def call(args, context: {})
        return "create_branch is disabled in read-only mode" if context[:read_only]

        root = context[:root] || Dir.pwd
        name = args["name"].to_s.gsub(/[^a-z0-9\-_]/, "-")
        base = args["base"] || "main"
        return "Error: name too generic" if name.match?(/\A(main|master|develop)\z/i)

        git_run("git checkout -b #{name} origin/#{base}", cwd: root)
      end
    end

    # Git push — push current branch to origin
    class GitPush < GitBase
      tool_name        "git_push"
      tool_description "Push current branch to origin remote"
      tool_risk        :medium
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      remote: { type: "string", description: "Remote name (default: origin)" },
                      branch: { type: "string", description: "Branch to push (default: current branch)" },
                      force: { type: "boolean", description: "Force push (use with extreme caution)" }
                    },
                    required: []
                  })

      def call(args, context: {})
        return "git_push is disabled in read-only mode" if context[:read_only]

        root   = context[:root] || Dir.pwd
        remote = args["remote"] || "origin"
        branch = args["branch"] || `git -C #{Shellwords.shellescape(root)} rev-parse --abbrev-ref HEAD`.strip
        force  = args["force"] ? "--force" : ""
        git_run("git push #{force} #{remote} #{Shellwords.shellescape(branch)}", cwd: root)
      end
    end

    # Git branch list — read-only
    class GitBranch < GitBase
      tool_name        "git_branch"
      tool_description "List branches or show current branch"
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      all: { type: "boolean", description: "Include remote branches" },
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
  end
end

OllamaAgent::Tools::EnhancedRegistry.register(OllamaAgent::Tools::GitStatus)
OllamaAgent::Tools::EnhancedRegistry.register(OllamaAgent::Tools::GitDiff)
OllamaAgent::Tools::EnhancedRegistry.register(OllamaAgent::Tools::GitLog)
OllamaAgent::Tools::EnhancedRegistry.register(OllamaAgent::Tools::GitCommit)
OllamaAgent::Tools::EnhancedRegistry.register(OllamaAgent::Tools::GitBranch)
OllamaAgent::Tools::EnhancedRegistry.register(OllamaAgent::Tools::GitCreateBranch)
OllamaAgent::Tools::EnhancedRegistry.register(OllamaAgent::Tools::GitPush)

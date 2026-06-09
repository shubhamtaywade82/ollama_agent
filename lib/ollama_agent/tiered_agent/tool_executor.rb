# frozen_string_literal: true

module OllamaAgent
  module TieredAgent
    # Sandboxed runtime layer for the three built-in tool actions.
    #
    # All shell execution passes through a deny-list of destructive patterns
    # before the command is forwarded to the OS. File I/O is bounded to the
    # paths returned by the planner; no path traversal escaping is attempted.
    class ToolExecutor
      SUPPORTED_TOOLS = %w[execute_bash read_source_file write_output_file].freeze

      # Patterns that indicate a destructive or injection-risk command.
      DANGEROUS_PATTERNS = [
        /\brm\s+-[a-z]*r[a-z]*f?\b/i,  # rm -rf, rm -fr, rm -r
        /\brm\s+-[a-z]*f[a-z]*r?\b/i,  # rm -f, rm -fR
        /\bdd\s+if=/i,                   # dd disk operations
        /\btruncate\s+/i,                # truncate file to zero
        /;\s*rm\b/,                      # chained ; rm
        /\|\s*rm\b/,                     # piped | rm
        /`[^`]*\brm\b/,                  # backtick subshell with rm
        /\$\([^)]*\brm\b/, # $(...) subshell with rm
        /\bmkfs\b/i,                     # filesystem format
        /\bfdisk\b/i,                    # partition table editor
        /\bshred\b/i,                    # secure-delete
        /\bwipefs\b/i,                   # wipe filesystem signatures
        %r{>\s*/dev/(sd|hd|nvme)}i # redirect directly to a block device
      ].freeze

      # @param name [String] tool name from {SUPPORTED_TOOLS}
      # @param args [Hash]   validated arguments from the extraction phase
      # @return [String] textual output for the verification phase
      def execute(name, args)
        case name
        when "execute_bash" then execute_bash(args)
        when "read_source_file" then read_file(args)
        when "write_output_file" then write_file(args)
        else
          "[Runtime Error] Unrecognized tool: #{name.inspect}."
        end
      rescue StandardError => e
        "[System Exception] #{e.message}"
      end

      private

      def execute_bash(args)
        command = args["command"].to_s.strip
        return "[Blocked] Empty command." if command.empty?
        return "[Blocked] Destructive command sequence detected." if dangerous?(command)

        `#{command} 2>&1`
      end

      def read_file(args)
        path = args["path"].to_s
        return "[Error] File path not found: #{path}" unless File.exist?(path)

        File.read(path)
      rescue Errno::EACCES => e
        "[Error] Permission denied reading #{path}: #{e.message}"
      end

      def write_file(args)
        path = args["path"].to_s
        return "[Error] No path specified." if path.empty?

        dir = File.dirname(path)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        File.write(path, args["data"].to_s)
        "[Success] Written to #{path}."
      rescue Errno::EACCES => e
        "[Error] Permission denied writing #{path}: #{e.message}"
      end

      def dangerous?(command)
        DANGEROUS_PATTERNS.any? { |pat| command.match?(pat) }
      end
    end
  end
end

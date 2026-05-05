# frozen_string_literal: true

require "open3"
require_relative "base"

module OllamaAgent
  module Tools
    # Safe shell command execution tool.
    #
    # Safety controls:
    #   - allowlist:  commands must match at least one allowlist pattern
    #   - denylist:   commands are rejected if they match any denylist pattern
    #   - dry_run:    if true, returns the command without executing
    #   - timeout:    kills the process after N seconds
    #   - redaction:  scrubs secret-like values from output
    #   - sandbox:    restricts working directory to project root
    # rubocop:disable Metrics/ClassLength -- single tool: policy tables + process I/O loop
    class RunShell < Base
      tool_name        "run_shell"
      tool_description "Execute a shell command in the project workspace (subject to allowlist/denylist rules)"
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      command: {
                        type: "string",
                        description: "Shell command to execute"
                      },
                      working_dir: {
                        type: "string",
                        description: "Working directory relative to project root (default: project root)"
                      },
                      timeout_seconds: {
                        type: "integer",
                        description: "Override execution timeout in seconds (max 120)",
                        minimum: 1,
                        maximum: 120
                      }
                    },
                    required: ["command"]
                  })

      DEFAULT_TIMEOUT = 30
      MAX_OUTPUT_BYTES = 65_536 # 64 KB

      # Default allowlist: common development workflows
      DEFAULT_ALLOWLIST = [
        /\Agit\s/,
        /\Abundle\s/,
        /\Arspec\b/,
        /\Arubocop\b/,
        /\Aruby\s/,
        /\Aecho\s/,
        /\Aprintf\s/,
        /\Acat\s/,
        /\Als\b/,
        /\Apwd\b/,
        /\Amkdir\s/,
        /\Acp\s/,
        /\Amv\s/,
        /\Awk\s/,
        /\Ased\s/,
        /\Agrep\s/,
        /\Afind\s/,
        /\Ayarn\s/,
        /\Anpm\s/,
        /\Amake\s/
      ].freeze

      # Default denylist: dangerous patterns regardless of allowlist
      DEFAULT_DENYLIST = [
        /rm\s+(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r|--recursive.*--force|--force.*--recursive)/i,
        /sudo\s/,
        /chmod\s+777/,
        /:\(\)\s*\{.*\}/, # fork bomb
        /curl[^|]*\|[^|]*sh/i,              # curl | bash
        /wget[^|]*\|[^|]*sh/i,              # wget | bash
        %r{>\s*/etc/},                       # write to /etc
        %r{>\s*/usr/},                       # write to /usr
        %r{dd\s+.*of=/dev/}i, # write to devices
        /mkfs\b/,                            # format filesystem
        /passwd\b/,                          # change passwords
        /visudo\b/,                          # edit sudoers
        /crontab\s+-[re]/i                   # modify crontabs
      ].freeze

      # Patterns that look like secrets — redacted from output
      SECRET_PATTERNS = [
        /(?:password|passwd|secret|api.?key|token|bearer)\s*[=:]\s*\S+/i,
        /AKIA[0-9A-Z]{16}/, # AWS access key
        /sk-[A-Za-z0-9]{32,}/, # OpenAI key pattern
        %r{eyJ[A-Za-z0-9+/=]{40,}} # JWT-ish
      ].freeze

      # rubocop:disable Metrics/ParameterLists -- explicit knobs for CLI/embedders
      def initialize(allowlist: nil, denylist: nil, timeout: DEFAULT_TIMEOUT,
                     dry_run: false, redact_secrets: true, **_opts)
        super()
        @allowlist       = allowlist      || DEFAULT_ALLOWLIST
        @denylist        = denylist       || DEFAULT_DENYLIST
        @timeout         = timeout
        @dry_run         = dry_run
        @redact_secrets  = redact_secrets
      end
      # rubocop:enable Metrics/ParameterLists

      def call(args, context: {})
        cmd = args["command"].to_s.strip
        return "Error: empty command" if cmd.empty?

        cwd     = resolve_cwd(args["working_dir"], context[:root])
        timeout = [args["timeout_seconds"]&.to_i || @timeout, 120].min

        check_allowlist!(cmd)
        check_denylist!(cmd)

        return { dry_run: true, command: cmd, cwd: cwd } if @dry_run || context[:read_only]

        run_command(cmd, cwd: cwd, timeout: timeout)
      end

      private

      def check_allowlist!(cmd)
        return if @allowlist.empty?
        return if @allowlist.any? { |pat| pat.match?(cmd) }

        raise OllamaAgent::Error,
              "Command blocked: not on allowlist. Command: #{cmd.inspect[0, 100]}"
      end

      def check_denylist!(cmd)
        match = @denylist.find { |pat| pat.match?(cmd) }
        return unless match

        raise OllamaAgent::Error,
              "Command blocked: matches denylist pattern #{match.inspect}. Command: #{cmd.inspect[0, 100]}"
      end

      def resolve_cwd(working_dir, root)
        base = File.expand_path(root || Dir.pwd)
        return base if working_dir.nil? || working_dir.strip.empty?

        candidate = File.expand_path(working_dir, base)
        # Enforce sandbox: cwd must stay inside project root
        raise OllamaAgent::Error, "working_dir must stay inside project root" unless candidate.start_with?(base)

        candidate
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- Open3 + timeout + aggregate result
      def run_command(cmd, cwd:, timeout:)
        stdout_buf = +""
        stderr_buf = +""
        exit_code  = nil

        begin
          Open3.popen3(cmd, chdir: cwd) do |_stdin, stdout, stderr, wait_thread|
            timed_out = stream_pump_timed_out?(stdout, stderr, stdout_buf, stderr_buf, timeout)
            if timed_out
              kill_process_safely(wait_thread.pid)
              return format_result("", "Timed out after #{timeout}s", 124)
            end

            drain_remaining!(stdout, stdout_buf)
            drain_remaining!(stderr, stderr_buf)
            exit_code = wait_thread.value.exitstatus
          end
        rescue Errno::ENOENT => e
          return "Error: #{e.message}"
        end

        truncate_output!(stdout_buf)
        truncate_output!(stderr_buf)

        format_result(redact(stdout_buf), redact(stderr_buf), exit_code)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # Returns true if the deadline elapsed before both streams finished.
      def stream_pump_timed_out?(stdout, stderr, stdout_buf, stderr_buf, timeout_seconds)
        monotonic_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

        while monotonic_now < monotonic_deadline
          readers = [stdout, stderr].reject(&:closed?)
          break if readers.empty?

          pump_ready_streams(ready_readers(readers), stdout, stderr, stdout_buf, stderr_buf)
          break if stdout.closed? && stderr.closed?
        end

        monotonic_now >= monotonic_deadline
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def ready_readers(readers)
        IO.select(readers, nil, nil, 0.1)&.first || []
      end

      def pump_ready_streams(ready, stdout, _stderr, stdout_buf, stderr_buf)
        ready.each do |io|
          target = io == stdout ? stdout_buf : stderr_buf
          append_nonblock!(io, target)
        end
      end

      def append_nonblock!(io, buf)
        buf << io.read_nonblock(4096)
      rescue Errno::EAGAIN, Errno::EINTR, IO::WaitReadable, EOFError
        nil
      end

      def drain_remaining!(io, buf)
        buf << io.read
      rescue IOError
        nil
      end

      def kill_process_safely(pid)
        Process.kill("TERM", pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      def truncate_output!(buf)
        return unless buf.bytesize > MAX_OUTPUT_BYTES

        buf.replace(buf.byteslice(0, MAX_OUTPUT_BYTES))
      end

      def format_result(stdout, stderr, exit_code)
        parts = []
        parts << stdout.strip unless stdout.strip.empty?
        parts << "STDERR: #{stderr.strip}" unless stderr.strip.empty?
        parts << "Exit code: #{exit_code}" unless exit_code.nil? || exit_code.zero?
        parts.empty? ? "(no output)" : parts.join("\n")
      end

      def redact(text)
        return text unless @redact_secrets

        SECRET_PATTERNS.reduce(text) { |t, pat| t.gsub(pat, "[REDACTED]") }
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

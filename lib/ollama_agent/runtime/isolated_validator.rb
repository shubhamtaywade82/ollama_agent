# frozen_string_literal: true

require "open3"

module OllamaAgent
  module Runtime
    # Runs array-exec validation commands inside a locked-down Docker container (no host shell).
    # rubocop:disable Metrics/ClassLength -- Docker argv + capture + status interpretation stay together
    class IsolatedValidator
      # @param image [String] Docker image reference (digest recorded when available).
      # @param workspace_root [String] host path bind-mounted read-only at /workspace.
      # @param runtime_command [String] container CLI executable name or path (default +docker+).
      # @param timeout_epochs [Integer] wall-clock seconds allowed for the container run (E7 naming; not logical epoch).
      # @param wal [WAL, nil] optional WAL for mutation_step audit rows.
      def initialize(image:, workspace_root:, runtime_command: "docker", timeout_epochs: 300, wal: nil)
        @image = image
        @workspace_root = File.expand_path(workspace_root)
        @runtime_command = runtime_command
        @timeout_epochs = timeout_epochs.to_i
        @wal = wal
        @digest_memo = :unset
        @runtime_checked = false
        @runtime_ok = false
      end

      # @param command [Array<String>] argv passed to the container entrypoint (no host shell).
      # @param manifest_id [String]
      # @param logical_stamp [String]
      # @return [Hash] keys: +:status+, +:exit_code+, +:stdout+, +:stderr+, +:image_digest+
      def run(command:, manifest_id:, logical_stamp:)
        assert_array_command!(command)
        digest = cached_image_digest
        return unavailable_result(digest) unless runtime_ok?

        argv = docker_argv(command)
        status, code, out, err = execute_docker(argv)
        result = base_result(status, code, out, err, digest)
        record_mutation_step(manifest_id, logical_stamp, result, command) if record_step?(status)
        result
      end

      private

      def unavailable_result(digest)
        base_result(:runtime_unavailable, nil, "", runtime_unavailable_message, digest)
      end

      def assert_array_command!(command)
        return if command.is_a?(Array) && command.all?(String)

        raise ArgumentError, "command must be Array<String> (array exec); got #{command.class}"
      end

      def docker_argv(command)
        exe = resolved_runtime_executable
        [
          exe, "run", "--rm",
          "--cap-drop=ALL", "--network=none", "--read-only",
          "--tmpfs=/tmp:rw,nosuid,size=64m", "--tmpfs=/log:rw,nosuid,size=32m",
          "--mount", workspace_bind_mount,
          "--user", "65532:65532",
          @image, *command
        ]
      end

      def workspace_bind_mount
        "type=bind,source=#{@workspace_root},target=/workspace,readonly"
      end

      def execute_docker(argv)
        out = +""
        err = +""
        status = popen3_status(argv, out, err)
        interpret_capture(out, err, status)
      rescue Errno::ENOENT => e
        [:runtime_unavailable, nil, "", e.message]
      end

      def popen3_status(argv, out_acc, err_acc)
        last = nil
        Open3.popen3(*argv) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          last = drain_or_timeout(stdout, stderr, wait_thr, out_acc, err_acc)
        end
        last
      end

      def drain_or_timeout(stdout, stderr, wait_thr, out_acc, err_acc)
        if wait_thr.join(@timeout_epochs)
          fill_streams(stdout, stderr, out_acc, err_acc)
          return wait_thr.value
        end

        kill_and_collect(wait_thr, stdout, stderr, out_acc, err_acc)
        nil
      end

      def fill_streams(stdout, stderr, out_acc, err_acc)
        out_acc << stdout.read
        err_acc << stderr.read
      end

      def kill_and_collect(wait_thr, stdout, stderr, out_acc, err_acc)
        Process.kill("KILL", wait_thr.pid)
        wait_thr.join(5)
        fill_streams(stdout, stderr, out_acc, err_acc)
      end

      def interpret_capture(stdout_str, stderr_str, last_status)
        return [:timeout, nil, stdout_str, stderr_str] if last_status.nil?

        code = last_status.exitstatus
        return [:runtime_unavailable, nil, stdout_str, stderr_str] if docker_daemon_error?(stderr_str, code)

        return [:ok, code, stdout_str, stderr_str] if code.zero?

        [:nonzero_exit, code, stdout_str, stderr_str]
      end

      def docker_daemon_error?(stderr_str, code)
        return true if code == 125

        msg = stderr_str.to_s
        msg.include?("Cannot connect to the Docker daemon") ||
          (msg.include?("permission denied") && msg.downcase.include?("docker"))
      end

      def base_result(status, code, out, err, digest)
        {
          status: status,
          exit_code: code,
          stdout: out.to_s,
          stderr: err.to_s,
          image_digest: digest
        }
      end

      def record_step?(status)
        @wal && %i[ok nonzero_exit].include?(status)
      end

      def record_mutation_step(manifest_id, logical_stamp, result, command)
        @wal.append_mutation_step(
          manifest_id: manifest_id,
          logical_stamp: logical_stamp,
          step: "isolated_validator",
          data: wal_step_data(result, command)
        )
      end

      def wal_step_data(result, command)
        {
          "status" => result[:status].to_s,
          "exit_code" => result[:exit_code],
          "command" => command,
          "image_digest" => result[:image_digest]
        }
      end

      def cached_image_digest
        return @digest_memo unless @digest_memo == :unset

        @digest_memo = fetch_image_digest
      end

      def fetch_image_digest
        exe = resolved_runtime_executable
        return nil unless exe

        out, _err, st = Open3.capture3(exe, "image", "inspect", "--format", "{{.Id}}", @image)
        return nil unless st.success?

        out.strip
      end

      def runtime_ok?
        return @runtime_ok if @runtime_checked

        @runtime_checked = true
        exe = resolved_runtime_executable
        return @runtime_ok = false unless exe

        _out, err, st = Open3.capture3(exe, "version", "--format", "{{.Client.Version}}")
        return @runtime_ok = false unless st.success?
        return @runtime_ok = false if err.to_s.match?(/command not found/i)

        @runtime_ok = true
      end

      def runtime_unavailable_message
        exe = resolved_runtime_executable
        return "#{@runtime_command}: not found on PATH" unless exe

        "docker runtime check failed for #{@runtime_command}"
      end

      def resolved_runtime_executable
        return @resolved_runtime_executable if defined?(@resolved_runtime_executable)

        @resolved_runtime_executable = locate_executable(@runtime_command)
      end

      def locate_executable(name)
        return name if name.include?(File::SEPARATOR) && File.executable?(name)

        paths = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
        hit = paths.filter_map { |dir| try_executable(File.join(dir, name)) }.first
        hit || try_executable(name)
      end

      def try_executable(path)
        path if File.executable?(path) && !File.directory?(path)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

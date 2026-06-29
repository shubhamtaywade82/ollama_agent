# frozen_string_literal: true

require "English"
require "json"
require "net/http"
require_relative "base"
require_relative "enhanced_registry"

module OllamaAgent
  module Tools
    class DockerRun < Base
      tool_name        "docker_run"
      tool_description "Run a command inside a Docker container for sandboxed execution. Requires docker on PATH."
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      image: { type: "string", description: "Docker image name" },
                      command: { type: "string", description: "Command to run inside the container" },
                      volumes: {
                        type: "array",
                        items: { type: "string" },
                        description: "Volume mounts as 'host:container' pairs"
                      },
                      env: {
                        type: "object",
                        description: "Environment variables as key-value pairs"
                      }
                    },
                    required: %w[image command]
                  })

      MAX_OUTPUT = 32_768

      def call(args, context: {})
        return "docker_run is disabled in read-only mode" if context[:read_only]

        image   = Shellwords.shellescape(args["image"])
        cmd     = Shellwords.shellescape(args["command"])
        vols    = Array(args["volumes"]).map { |v| "-v #{Shellwords.shellescape(v)}" }.join(" ")
        envs    = (args["env"] || {}).map { |k, v| "-e #{Shellwords.shellescape(k)}=#{Shellwords.shellescape(v)}" }.join(" ")

        docker_cmd = "docker run --rm #{vols} #{envs} #{image} #{cmd} 2>&1"
        out = `#{docker_cmd}`
        exit_code = $CHILD_STATUS.exitstatus

        {
          exit_code: exit_code,
          output: out.byteslice(0, MAX_OUTPUT)
        }
      rescue StandardError => e
        { error: e.message }
      end
    end

    class CiTrigger < Base
      tool_name        "ci_trigger"
      tool_description "Trigger a GitHub Actions workflow dispatch. Requires GITHUB_TOKEN."
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      workflow: { type: "string", description: "Workflow file name (e.g. 'ci.yml')" },
                      branch: { type: "string", description: "Branch to run on (default: main)" },
                      repo: { type: "string", description: "Repo in owner/name format" },
                      inputs: {
                        type: "object",
                        description: "Optional workflow dispatch inputs"
                      }
                    },
                    required: %w[workflow repo]
                  })

      def call(args, context: {})
        return "ci_trigger is disabled in read-only mode" if context[:read_only]

        token = ENV.fetch("GITHUB_TOKEN", nil)
        return "Error: GITHUB_TOKEN not set" unless token && !token.empty?

        repo     = args["repo"]
        workflow = args["workflow"]
        branch   = args["branch"] || "main"
        inputs   = args["inputs"] || {}

        uri  = URI("https://api.github.com/repos/#{repo}/actions/workflows/#{workflow}/dispatches")
        req  = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{token}"
        req["Content-Type"]  = "application/json"
        req.body = JSON.generate({ ref: branch, inputs: inputs })

        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 15) { |h| h.request(req) }
        return "HTTP #{resp.code}: #{resp.message}" unless resp.is_a?(Net::HTTPSuccess) || resp.is_a?(Net::HTTPNoContent)

        "Workflow #{workflow} triggered on #{repo}@#{branch}"
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end

    class ReadCiLogs < Base
      tool_name        "read_ci_logs"
      tool_description "Fetch GitHub Actions run logs. Requires GITHUB_TOKEN."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      repo: { type: "string", description: "Repo in owner/name format" },
                      run_id: { type: "integer", description: "GitHub Actions run ID" }
                    },
                    required: %w[repo run_id]
                  })

      MAX_BYTES = 32_768

      def call(args, _context = {})
        token = ENV.fetch("GITHUB_TOKEN", nil)
        return "Error: GITHUB_TOKEN not set" unless token && !token.empty?

        repo   = args["repo"]
        run_id = args["run_id"]

        uri  = URI("https://api.github.com/repos/#{repo}/actions/runs/#{run_id}/logs")
        req  = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{token}"
        req["Accept"]        = "application/vnd.github+json"

        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 30) { |h| h.request(req) }
        return "HTTP #{resp.code}" unless resp.is_a?(Net::HTTPSuccess)

        body = resp.body.to_s.encode("UTF-8", invalid: :replace, undef: :replace)
        body = "#{body.byteslice(0, MAX_BYTES)}\n...[truncated]" if body.bytesize > MAX_BYTES
        { logs: body, run_id: run_id }
      rescue StandardError => e
        { error: e.message }
      end
    end

    class EnvGet < Base
      tool_name        "env_get"
      tool_description "Read a non-sensitive allowlisted environment variable."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      key: {
                        type: "string",
                        enum: %w[RAILS_ENV NODE_ENV APP_ENV RACK_ENV OLLAMA_AGENT_MODEL
                                 OLLAMA_HOST OLLAMA_AGENT_LOG_LEVEL OLLAMA_AGENT_DEBUG
                                 OLLAMA_AGENT_ROOT OLLAMA_AGENT_MAX_TURNS HOME USER SHELL],
                        description: "Environment variable key"
                      }
                    },
                    required: ["key"]
                  })

      def call(args, _context = {})
        key = args["key"].to_s
        value = ENV.fetch(key, nil)
        value.nil? ? "ENV[#{key}] is not set" : value
      end
    end

    EnhancedRegistry.register(DockerRun)
    EnhancedRegistry.register(CiTrigger)
    EnhancedRegistry.register(ReadCiLogs)
    EnhancedRegistry.register(EnvGet)
  end
end

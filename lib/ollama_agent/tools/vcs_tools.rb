# frozen_string_literal: true

require "json"
require_relative "base"
require_relative "enhanced_registry"

module OllamaAgent
  module Tools
    class OpenPullRequest < Base
      tool_name        "open_pull_request"
      tool_description "Push current branch and open a GitHub PR. Requires GITHUB_TOKEN env var."
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      title: { type: "string", description: "PR title" },
                      body: { type: "string", description: "PR body / description" },
                      repo: { type: "string", description: "repo in owner/name format (default: from git remote)" },
                      base: { type: "string", description: "Target branch (default: main)" }
                    },
                    required: ["title"]
                  })

      def call(args, context: {})
        return "open_pull_request is disabled in read-only mode" if context[:read_only]

        token = ENV["GITHUB_TOKEN"]
        return "Error: GITHUB_TOKEN not set" unless token && !token.empty?

        root  = context[:root] || Dir.pwd
        title = args["title"].to_s
        body  = args["body"].to_s
        base  = args["base"] || "main"

        branch = `git -C #{Shellwords.shellescape(root)} rev-parse --abbrev-ref HEAD`.strip
        `git -C #{Shellwords.shellescape(root)} push -u origin #{Shellwords.shellescape(branch)} 2>&1`

        repo = args["repo"] || repo_from_remote(root)
        return "Error: could not determine repo" unless repo

        uri = URI("https://api.github.com/repos/#{repo}/pulls")
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{token}"
        req["Content-Type"]  = "application/json"
        req.body = JSON.generate({ title: title, body: body, head: branch, base: base })

        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 15) { |h| h.request(req) }
        return "HTTP #{resp.code}: #{resp.message}" unless resp.is_a?(Net::HTTPSuccess)

        data = JSON.parse(resp.body)
        "PR created: #{data["html_url"]}"
      rescue StandardError => e
        "Error: #{e.message}"
      end

      private

      def repo_from_remote(root)
        remote = `git -C #{Shellwords.shellescape(root)} remote get-url origin 2>/dev/null`.strip
        return nil if remote.empty?

        match = remote.match(%r{(?:github\.com[:/])([^/]+/[^/.]+)})
        match&.[](1)
      end
    end

    EnhancedRegistry.register(OpenPullRequest)
  end
end

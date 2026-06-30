# frozen_string_literal: true

require "net/http"
require "json"
require_relative "base"
require_relative "enhanced_registry"

module OllamaAgent
  module Tools
    class GithubComment < Base
      tool_name        "github_comment"
      tool_description "Post a review comment on a GitHub PR issue. Requires GITHUB_TOKEN."
      tool_risk        :medium
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      repo: { type: "string", description: "Repository in owner/name format" },
                      pr_number: { type: "integer", description: "PR or issue number" },
                      body: { type: "string", description: "Comment body / message" }
                    },
                    required: %w[repo pr_number body]
                  })

      def call(args, context: {})
        return "github_comment is disabled in read-only mode" if context[:read_only]

        token = ENV.fetch("GITHUB_TOKEN", nil)
        return "Error: GITHUB_TOKEN not set" unless token && !token.empty?

        repo  = args["repo"]
        pr    = args["pr_number"]
        body  = args["body"]

        uri  = URI("https://api.github.com/repos/#{repo}/issues/#{pr}/comments")
        req  = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{token}"
        req["Content-Type"]  = "application/json"
        req.body = JSON.generate({ body: body })

        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 15) { |h| h.request(req) }
        return "HTTP #{resp.code}: #{resp.message}" unless resp.is_a?(Net::HTTPSuccess)

        data = JSON.parse(resp.body)
        "Comment posted: #{data["html_url"]}"
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end

    class FetchUrl < Base
      tool_name        "fetch_url"
      tool_description "Fetch a URL and return text content with HTML stripped. For reading docs, changelogs."
      tool_risk        :medium
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      url: { type: "string", description: "Full URL to fetch", minLength: 5 },
                      max_chars: { type: "integer", description: "Max characters to return (default: 8000, max: 32000)" }
                    },
                    required: ["url"]
                  })

      MAX_CHARS = 8000
      ABSOLUTE_MAX = 32_000
      ALLOWED_TYPES = %w[text/html text/plain text/markdown application/json].freeze

      def call(args, _context = {})
        url  = args["url"].to_s.strip
        max  = [args["max_chars"]&.to_i || MAX_CHARS, ABSOLUTE_MAX].min
        uri  = URI.parse(url)

        resp = Net::HTTP.get_response(uri)
        return "HTTP #{resp.code}" unless resp.is_a?(Net::HTTPSuccess)

        ct = resp["content-type"].to_s.split(";").first.strip
        return "Blocked: content-type #{ct}" unless ALLOWED_TYPES.any? { |t| ct.start_with?(t) }

        text = resp.body.encode("UTF-8", invalid: :replace, undef: :replace)
        text = text.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
        text = "#{text[0, max]}\n...[truncated]" if text.size > max
        { content: text, status: resp.code.to_i, url: url }
      rescue StandardError => e
        { error: e.message }
      end
    end

    EnhancedRegistry.register(GithubComment)
    EnhancedRegistry.register(FetchUrl)
  end
end

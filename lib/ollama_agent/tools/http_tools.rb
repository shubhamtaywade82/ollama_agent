# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "base"

module OllamaAgent
  module Tools
    # @api private
    module HttpHostPattern
      class << self
        def match?(pattern, host)
          pattern.is_a?(Regexp) ? pattern.match?(host) : pattern == host
        end
      end
    end

    # HTTP GET tool — for fetching documentation, APIs, public resources.
    # rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize -- schema + URL policy + Net::HTTP
    class HttpGet < Base
      tool_name        "http_get"
      tool_description "Fetch a URL via HTTP GET and return the response body (text/JSON only)"
      tool_risk        :medium
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      url: {
                        type: "string",
                        description: "Full URL to fetch (must be https:// or http://)",
                        minLength: 10
                      },
                      headers: {
                        type: "object",
                        description: "Optional HTTP headers as key-value pairs"
                      },
                      max_bytes: {
                        type: "integer",
                        description: "Truncate response at this many bytes (default 32768, max 131072)",
                        minimum: 1,
                        maximum: 131_072
                      }
                    },
                    required: ["url"]
                  })

      DEFAULT_MAX_BYTES = 32_768
      ALLOWED_SCHEMES   = %w[http https].freeze
      ALLOWED_CONTENT_TYPES = %w[
        text/plain text/html text/markdown application/json application/xml
        text/xml text/csv application/yaml text/yaml
      ].freeze

      def initialize(allowed_hosts: nil, denied_hosts: nil, timeout: 15, **_opts)
        super()
        @allowed_hosts = allowed_hosts
        @denied_hosts  = Array(denied_hosts)
        @timeout       = timeout
      end

      def call(args, _context: {})
        url       = args["url"].to_s.strip
        max_bytes = [args["max_bytes"]&.to_i || DEFAULT_MAX_BYTES, 131_072].min

        uri = parse_and_validate_url!(url)
        check_host!(uri.host)

        headers = build_headers(args["headers"])
        fetch(uri, headers: headers, max_bytes: max_bytes)
      end

      private

      def parse_and_validate_url!(url)
        uri = URI.parse(url)
        unless ALLOWED_SCHEMES.include?(uri.scheme)
          raise OllamaAgent::Error, "http_get: only #{ALLOWED_SCHEMES.join("/")} URLs are allowed"
        end

        uri
      rescue URI::InvalidURIError => e
        raise OllamaAgent::Error, "http_get: invalid URL — #{e.message}"
      end

      def check_host!(host)
        if @allowed_hosts&.none? { |pat| HttpHostPattern.match?(pat, host) }
          raise OllamaAgent::Error, "http_get: host #{host} is not on the allowlist"
        end

        if @denied_hosts.any? { |pat| HttpHostPattern.match?(pat, host) }
          raise OllamaAgent::Error, "http_get: host #{host} is blocked"
        end

        # Block private/internal addresses
        return unless private_address?(host)

        raise OllamaAgent::Error, "http_get: requests to internal/private addresses are blocked"
      end

      def private_address?(host)
        return false if host.nil?

        private_patterns = [
          /\A127\./,
          /\A10\./,
          /\A172\.(1[6-9]|2\d|3[01])\./,
          /\A192\.168\./,
          /\Alocalhost\z/i,
          /\A::1\z/,
          /\A0\.0\.0\.0\z/,
          /\.local\z/i
        ]
        private_patterns.any? { |pat| pat.match?(host) }
      end

      def build_headers(custom)
        headers = {
          "User-Agent" => "OllamaAgent/#{begin
            OllamaAgent::VERSION
          rescue StandardError
            "0"
          end} (+https://github.com/shubhamtaywade82/ollama_agent)"
        }
        return headers unless custom.is_a?(Hash)

        # Strip dangerous headers
        safe_custom = custom.reject { |k, _| k.to_s.downcase.match?(/authorization|cookie|set-cookie/) }
        headers.merge(safe_custom)
      end

      def fetch(uri, headers:, max_bytes:)
        use_ssl  = uri.scheme == "https"
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: use_ssl,
                                                       read_timeout: @timeout, open_timeout: 5) do |http|
          req = Net::HTTP::Get.new(uri)
          headers.each { |k, v| req[k] = v }
          http.request(req)
        end

        handle_response(response, max_bytes)
      rescue Net::OpenTimeout, Net::ReadTimeout
        "Error: request timed out after #{@timeout}s"
      rescue SocketError => e
        "Error: #{e.message}"
      end

      def handle_response(resp, max_bytes)
        status = resp.code.to_i
        ct     = resp["content-type"].to_s.split(";").first.strip

        return "HTTP #{status}: #{resp.message}" unless (200..299).cover?(status)

        unless ALLOWED_CONTENT_TYPES.any? { |allowed| ct.start_with?(allowed) }
          return "Blocked: content-type #{ct.inspect} is not a text or JSON type"
        end

        body = resp.body.to_s.encode("UTF-8", invalid: :replace, undef: :replace)
        body = "#{body.byteslice(0, max_bytes)}\n...[truncated]" if body.bytesize > max_bytes
        body
      end
    end
    # rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize

    # HTTP POST tool — for sending data to APIs
    class HttpPost < Base
      tool_name        "http_post"
      tool_description "Send a JSON POST request to an API endpoint"
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      url: { type: "string", description: "Full URL", minLength: 10 },
                      body: { type: "object", description: "JSON body to send" },
                      headers: { type: "object", description: "Optional HTTP headers" }
                    },
                    required: %w[url body]
                  })

      def initialize(allowed_hosts: nil, timeout: 30, **_opts)
        super()
        @allowed_hosts = allowed_hosts
        @timeout       = timeout
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def call(args, context: {})
        return "http_post is disabled in read-only mode" if context[:read_only]

        url  = args["url"].to_s.strip
        body = args["body"]

        uri = URI.parse(url)
        raise OllamaAgent::Error, "http_post: only https/http URLs" unless %w[http https].include?(uri.scheme)

        if @allowed_hosts&.none? { |pat| HttpHostPattern.match?(pat, uri.host) }
          raise OllamaAgent::Error, "http_post: host #{uri.host} not on allowlist"
        end

        headers = (args["headers"] || {}).merge("Content-Type" => "application/json")

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                            read_timeout: @timeout, open_timeout: 5) do |http|
          req = Net::HTTP::Post.new(uri)
          headers.each { |k, v| req[k] = v }
          req.body = JSON.generate(body)
          resp     = http.request(req)
          "HTTP #{resp.code}: #{resp.body.to_s.byteslice(0, 8192)}"
        end
      rescue StandardError => e
        "Error: #{e.message}"
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    end
  end
end

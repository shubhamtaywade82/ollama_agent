# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module OllamaAgent
  module LLM
    # Direct HTTPS client for Anthropic Messages API (no shell-out).
    # Uses only Net::HTTP timeouts — no wall-clock Time.now on the request path.
    class AnthropicClient
      API_URL = "https://api.anthropic.com/v1/messages"
      ANTHROPIC_VERSION = "2023-06-01"

      def initialize(api_key:, model: "claude-opus-4-7", timeout_seconds: 180, http_client: Net::HTTP)
        @api_key = api_key
        @model = model
        @timeout_seconds = Integer(timeout_seconds)
        @http_client = http_client
      end

      # @return [Hash] +:content+ (assistant text), +:stop_reason+, +:usage+ (symbol keys)
      def chat(messages:, system: nil, max_tokens: 8192)
        body = build_body(messages: messages, system: system, max_tokens: max_tokens)
        response = post_json(body)
        raise AnthropicAPIError, error_message_for(response) unless response.code == "200"

        parse_success_response(response.body)
      end

      private

      def build_body(messages:, system:, max_tokens:)
        payload = {
          "model" => @model,
          "max_tokens" => Integer(max_tokens),
          "messages" => normalize_messages(messages)
        }
        payload["system"] = system if system && !system.to_s.empty?
        payload
      end

      def normalize_messages(messages)
        Array(messages).map do |m|
          {
            "role" => (m["role"] || m[:role]).to_s,
            "content" => (m["content"] || m[:content]).to_s
          }
        end
      end

      def post_json(payload)
        uri = URI(API_URL)
        open_http(uri).request(build_post(uri, payload))
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT => e
        raise AnthropicAPIError, "HTTP timeout: #{e.class}: #{e.message}"
      end

      def open_http(uri)
        http = @http_client.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = @timeout_seconds
        http.read_timeout = @timeout_seconds
        http
      end

      def build_post(uri, payload)
        req = Net::HTTP::Post.new(uri.request_uri)
        req["x-api-key"] = @api_key
        req["anthropic-version"] = ANTHROPIC_VERSION
        req["content-type"] = "application/json"
        req.body = JSON.generate(payload)
        req
      end

      def error_message_for(response)
        "Anthropic API status=#{response.code} body=#{response.body}"
      end

      def parse_success_response(body)
        data = JSON.parse(body)
        text = extract_text_block(data)
        {
          content: text,
          stop_reason: data["stop_reason"],
          usage: normalize_usage(data["usage"])
        }
      end

      def extract_text_block(data)
        block = Array(data["content"]).find { |c| c["type"] == "text" }
        block ? block["text"].to_s : ""
      end

      def normalize_usage(raw)
        usage = raw || {}
        {
          input_tokens: usage["input_tokens"],
          output_tokens: usage["output_tokens"]
        }
      end
    end
  end
end

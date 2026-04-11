# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "base"

module OllamaAgent
  module Providers
    # OpenAI provider — talks to the OpenAI Chat Completions API (or any compatible endpoint).
    # Also works with Azure OpenAI, Together AI, Groq, and other OpenAI-compatible APIs
    # by setting :base_url.
    #
    # @example
    #   provider = OllamaAgent::Providers::OpenAI.new(api_key: ENV["OPENAI_API_KEY"])
    #   response = provider.chat(messages: [...], model: "gpt-4o")
    class OpenAI < Base
      API_BASE     = "https://api.openai.com/v1"
      DEFAULT_MODEL = "gpt-4o-mini"

      # Pricing per 1K tokens (USD) — update as needed
      PRICING = {
        "gpt-4o"       => { input: 0.0025,  output: 0.010 },
        "gpt-4o-mini"  => { input: 0.00015, output: 0.0006 },
        "gpt-4-turbo"  => { input: 0.010,   output: 0.030 },
        "gpt-3.5-turbo"=> { input: 0.0005,  output: 0.0015 }
      }.freeze

      def initialize(api_key: nil, base_url: nil, organization: nil, timeout: 60, **opts)
        super(name: "openai", **opts)
        @api_key      = api_key      || ENV.fetch("OPENAI_API_KEY", nil)
        @base_url     = base_url     || ENV.fetch("OPENAI_BASE_URL", API_BASE)
        @organization = organization || ENV.fetch("OPENAI_ORG_ID", nil)
        @timeout      = timeout
      end

      # @param messages [Array<Hash>]
      # @param model    [String]
      # @param tools    [Array<Hash>]  nil = no tools
      # @param stream_hooks [Hash]     :on_token lambda (streaming)
      # @param temperature [Float]
      # @return [Response]
      def chat(messages:, model: nil, tools: nil, stream_hooks: nil, temperature: 0.2, **_opts)
        raise ConfigurationError, "OpenAI API key not set (OPENAI_API_KEY)" unless @api_key

        model ||= DEFAULT_MODEL
        body   = build_body(messages: messages, model: model, tools: tools,
                            temperature: temperature, stream: !stream_hooks.nil?)

        if stream_hooks
          stream_chat(body, model, stream_hooks)
        else
          blocking_chat(body, model)
        end
      end

      def available?
        !@api_key.nil?
      end

      def streaming_supported?
        true
      end

      def estimate_cost(input_tokens:, output_tokens:, model: DEFAULT_MODEL)
        pricing = PRICING[model] || PRICING[DEFAULT_MODEL]
        (input_tokens  / 1000.0 * pricing[:input]) +
          (output_tokens / 1000.0 * pricing[:output])
      end

      private

      def build_body(messages:, model:, tools:, temperature:, stream: false)
        body = {
          model:       model,
          messages:    normalize_messages(messages),
          temperature: temperature,
          stream:      stream
        }
        body[:tools] = tools if tools && !tools.empty?
        body
      end

      def blocking_chat(body, model)
        raw    = post("/chat/completions", body)
        choice = raw.dig("choices", 0)
        raise OllamaAgent::Error, "Empty response from OpenAI" if choice.nil?

        message = choice["message"]
        usage   = raw["usage"]

        Response.new(
          message:  normalize_message(message),
          usage:    normalize_usage(usage),
          provider: "openai",
          model:    model
        )
      end

      def stream_chat(body, model, hooks)
        collected_content  = +""
        collected_calls    = []

        post_stream("/chat/completions", body) do |chunk|
          delta = chunk.dig("choices", 0, "delta") || {}
          if (token = delta["content"])
            collected_content << token
            hooks[:on_token]&.call(token)
          end
          if (tc = delta["tool_calls"])
            tc.each { |t| merge_tool_call(collected_calls, t) }
          end
        end

        message = { role: "assistant", content: collected_content, tool_calls: collected_calls }
        Response.new(message: message, usage: nil, provider: "openai", model: model)
      end

      def normalize_messages(messages)
        messages.map { |m| m.transform_keys(&:to_s) }
      end

      def normalize_message(msg)
        {
          role:       msg["role"],
          content:    msg["content"],
          tool_calls: (msg["tool_calls"] || []).map { |tc| normalize_tool_call_response(tc) }
        }
      end

      def normalize_tool_call_response(tc)
        {
          id:       tc["id"],
          type:     "function",
          function: { name: tc.dig("function", "name"), arguments: parse_args(tc.dig("function", "arguments")) }
        }
      end

      def parse_args(raw)
        return raw if raw.is_a?(Hash)

        JSON.parse(raw.to_s)
      rescue JSON::ParserError
        {}
      end

      def normalize_usage(usage)
        return nil unless usage

        {
          prompt_tokens:     usage["prompt_tokens"].to_i,
          completion_tokens: usage["completion_tokens"].to_i,
          total_tokens:      usage["total_tokens"].to_i
        }
      end

      def merge_tool_call(calls, delta)
        idx = delta["index"].to_i
        calls[idx] ||= { id: nil, type: "function", function: { name: +"", arguments: +"" } }
        calls[idx][:id]                  = delta["id"] if delta["id"]
        calls[idx][:function][:name]     << delta.dig("function", "name").to_s
        calls[idx][:function][:arguments] << delta.dig("function", "arguments").to_s
      end

      def post(path, body)
        uri  = URI("#{@base_url}#{path}")
        req  = build_http_request(uri, body)
        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               read_timeout: @timeout, open_timeout: 10) { |http| http.request(req) }
        handle_response(resp)
      end

      def post_stream(path, body)
        uri = URI("#{@base_url}#{path}")
        req = build_http_request(uri, body)

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                        read_timeout: @timeout, open_timeout: 10) do |http|
          http.request(req) do |resp|
            resp.read_body do |chunk|
              chunk.split("\n").each do |line|
                next unless line.start_with?("data: ")

                data = line.sub("data: ", "").strip
                next if data == "[DONE]"

                parsed = JSON.parse(data) rescue next
                yield parsed
              end
            end
          end
        end
      end

      def build_http_request(uri, body)
        req = Net::HTTP::Post.new(uri)
        req["Authorization"]  = "Bearer #{@api_key}"
        req["Content-Type"]   = "application/json"
        req["OpenAI-Organization"] = @organization if @organization
        req.body = JSON.generate(body)
        req
      end

      def handle_response(resp)
        body = JSON.parse(resp.body)
        case resp.code.to_i
        when 200..299 then body
        when 401 then raise OllamaAgent::Error, "OpenAI: unauthorized — check OPENAI_API_KEY"
        when 429 then raise OllamaAgent::Error, "OpenAI: rate limited"
        else          raise OllamaAgent::Error, "OpenAI error #{resp.code}: #{body["error"]&.dig("message")}"
        end
      end
    end
  end
end

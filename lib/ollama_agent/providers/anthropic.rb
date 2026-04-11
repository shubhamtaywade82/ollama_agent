# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "base"

module OllamaAgent
  module Providers
    # Anthropic provider — talks to the Claude Messages API.
    #
    # @example
    #   provider = OllamaAgent::Providers::Anthropic.new(api_key: ENV["ANTHROPIC_API_KEY"])
    #   response = provider.chat(messages: [...], model: "claude-3-5-sonnet-20241022")
    class Anthropic < Base
      API_BASE       = "https://api.anthropic.com/v1"
      API_VERSION    = "2023-06-01"
      DEFAULT_MODEL  = "claude-3-5-haiku-20241022"
      DEFAULT_TOKENS = 4096

      # Pricing per 1M tokens (USD)
      PRICING = {
        "claude-opus-4-5"             => { input: 15.0,  output: 75.0 },
        "claude-sonnet-4-5"           => { input:  3.0,  output: 15.0 },
        "claude-3-5-sonnet-20241022"  => { input:  3.0,  output: 15.0 },
        "claude-3-5-haiku-20241022"   => { input:  0.8,  output:  4.0 },
        "claude-3-haiku-20240307"     => { input:  0.25, output:  1.25 }
      }.freeze

      def initialize(api_key: nil, beta_headers: nil, timeout: 120, **opts)
        super(name: "anthropic", **opts)
        @api_key      = api_key      || ENV.fetch("ANTHROPIC_API_KEY", nil)
        @beta_headers = beta_headers || []
        @timeout      = timeout
      end

      # @param messages [Array<Hash>]
      # @param model    [String]
      # @param tools    [Array<Hash>]   Anthropic-format or OpenAI-format (auto-converted)
      # @param stream_hooks [Hash]      :on_token, :on_thinking lambdas
      # @param max_tokens [Integer]
      # @param temperature [Float]
      # @param system [String, nil]     system prompt (extracted from messages if not given)
      # @return [Response]
      def chat(messages:, model: nil, tools: nil, stream_hooks: nil,
               max_tokens: DEFAULT_TOKENS, temperature: 0.2, system: nil, **_opts)
        raise ConfigurationError, "Anthropic API key not set (ANTHROPIC_API_KEY)" unless @api_key

        model ||= DEFAULT_MODEL
        system_prompt, user_messages = split_system(messages, system)

        body = build_body(
          messages: user_messages, model: model, tools: tools,
          max_tokens: max_tokens, temperature: temperature,
          system: system_prompt, stream: !stream_hooks.nil?
        )

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
        (input_tokens  / 1_000_000.0 * pricing[:input]) +
          (output_tokens / 1_000_000.0 * pricing[:output])
      end

      private

      def split_system(messages, explicit_system)
        system_msgs = messages.select { |m| (m[:role] || m["role"]) == "system" }
        user_msgs   = messages.reject { |m| (m[:role] || m["role"]) == "system" }

        system_text = explicit_system ||
                      system_msgs.map { |m| m[:content] || m["content"] }.join("\n\n")
        system_text = nil if system_text.to_s.strip.empty?

        [system_text, user_msgs]
      end

      def build_body(messages:, model:, tools:, max_tokens:, temperature:, system:, stream:)
        body = {
          model:       model,
          messages:    normalize_messages(messages),
          max_tokens:  max_tokens,
          temperature: temperature,
          stream:      stream
        }
        body[:system] = system if system
        body[:tools]  = convert_tools(tools) if tools && !tools.empty?
        body
      end

      def blocking_chat(body, model)
        raw = post("/messages", body)
        build_response(raw, model)
      end

      def stream_chat(body, model, hooks)
        collected_content = +""
        collected_calls   = []

        post_stream("/messages", body) do |event|
          case event["type"]
          when "content_block_delta"
            delta = event.dig("delta") || {}
            case delta["type"]
            when "text_delta"
              token = delta["text"].to_s
              collected_content << token
              hooks[:on_token]&.call(token)
            when "thinking_delta"
              hooks[:on_thinking]&.call(delta["thinking"].to_s)
            when "input_json_delta"
              # accumulate tool input
              idx = event["index"].to_i
              collected_calls[idx] ||= { partial_json: +"" }
              collected_calls[idx][:partial_json] << delta["partial_json"].to_s
            end
          when "content_block_start"
            block = event["content_block"] || {}
            if block["type"] == "tool_use"
              idx = event["index"].to_i
              collected_calls[idx] = { id: block["id"], name: block["name"], partial_json: +"" }
            end
          end
        end

        tool_calls = collected_calls.compact.map { |tc| finalize_tool_call(tc) }
        message = { role: "assistant", content: collected_content, tool_calls: tool_calls }
        Response.new(message: message, usage: nil, provider: "anthropic", model: model)
      end

      def build_response(raw, model)
        content_blocks = raw["content"] || []
        text_parts     = content_blocks.select { |b| b["type"] == "text" }.map { |b| b["text"] }.join
        tool_calls     = content_blocks.select { |b| b["type"] == "tool_use" }.map { |b| normalize_tool_use(b) }

        message = { role: "assistant", content: text_parts, tool_calls: tool_calls }
        usage   = normalize_usage(raw["usage"])

        Response.new(message: message, usage: usage, provider: "anthropic", model: model)
      end

      def normalize_tool_use(block)
        {
          id:       block["id"],
          type:     "function",
          function: { name: block["name"], arguments: block["input"] || {} }
        }
      end

      def finalize_tool_call(tc)
        args = begin
          JSON.parse(tc[:partial_json])
        rescue StandardError
          {}
        end
        { id: tc[:id], type: "function", function: { name: tc[:name], arguments: args } }
      end

      def convert_tools(tools)
        tools.map do |t|
          fn = t[:function] || t["function"] || t
          {
            name:         fn[:name] || fn["name"],
            description:  fn[:description] || fn["description"],
            input_schema: fn[:parameters] || fn["parameters"] || {}
          }
        end
      end

      def normalize_messages(messages)
        messages.map { |m| { role: (m[:role] || m["role"]), content: (m[:content] || m["content"]).to_s } }
      end

      def normalize_usage(usage)
        return nil unless usage

        input  = usage["input_tokens"].to_i
        output = usage["output_tokens"].to_i
        { prompt_tokens: input, completion_tokens: output, total_tokens: input + output }
      end

      def post(path, body)
        uri  = URI("#{API_BASE}#{path}")
        req  = build_request(uri, body)
        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                               read_timeout: @timeout, open_timeout: 10) { |http| http.request(req) }
        handle_response(resp)
      end

      def post_stream(path, body)
        uri = URI("#{API_BASE}#{path}")
        req = build_request(uri, body)

        Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                        read_timeout: @timeout, open_timeout: 10) do |http|
          http.request(req) do |resp|
            resp.read_body do |chunk|
              chunk.split("\n").each do |line|
                next unless line.start_with?("data: ")

                data = line.sub("data: ", "").strip
                parsed = JSON.parse(data) rescue next
                yield parsed
              end
            end
          end
        end
      end

      def build_request(uri, body)
        req = Net::HTTP::Post.new(uri)
        req["x-api-key"]         = @api_key
        req["anthropic-version"] = API_VERSION
        req["Content-Type"]      = "application/json"
        req["anthropic-beta"]    = @beta_headers.join(",") if @beta_headers.any?
        req.body = JSON.generate(body)
        req
      end

      def handle_response(resp)
        parsed = JSON.parse(resp.body)
        case resp.code.to_i
        when 200..299 then parsed
        when 401 then raise OllamaAgent::Error, "Anthropic: unauthorized — check ANTHROPIC_API_KEY"
        when 429 then raise OllamaAgent::Error, "Anthropic: rate limited"
        else          raise OllamaAgent::Error, "Anthropic #{resp.code}: #{parsed.dig("error", "message")}"
        end
      end
    end
  end
end

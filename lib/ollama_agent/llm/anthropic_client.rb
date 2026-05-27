# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module OllamaAgent
  module LLM
    # Direct HTTPS client for Anthropic Messages API (no shell-out).
    # Retry backoff uses wall-clock sleep (not for saga logical clocks).
    #
    # rubocop:disable Metrics/ClassLength -- single-file HTTP + SSE client without extra gem deps
    class AnthropicClient
      API_URL = "https://api.anthropic.com/v1/messages"
      ANTHROPIC_VERSION = "2023-06-01"
      RETRYABLE_STATUSES = [429, 502, 503, 504].freeze
      DEFAULT_MAX_ATTEMPTS = 3
      DEFAULT_BASE_DELAY = 1.0
      BACKOFF_FACTOR = 2.0
      JITTER_LOW = 0.75
      JITTER_HIGH = 1.25

      attr_reader :model

      # @param open_timeout_seconds [Integer] TCP connect timeout
      # @param request_timeout_seconds [Integer] read timeout per request
      # @param timeout_seconds [Integer, nil] when set, used for both open and read (backwards compatible)
      # rubocop:disable Metrics/ParameterLists -- explicit test hooks + timeout knobs
      def initialize(
        api_key:,
        model: "claude-opus-4-7",
        timeout_seconds: nil,
        open_timeout_seconds: nil,
        request_timeout_seconds: nil,
        max_attempts: DEFAULT_MAX_ATTEMPTS,
        sleep: Kernel.method(:sleep),
        random: Random.new,
        http_client: Net::HTTP
      )
        @api_key = api_key
        @model = model
        @open_timeout = Integer(open_timeout_seconds || timeout_seconds || 180)
        @request_timeout = Integer(request_timeout_seconds || timeout_seconds || 180)
        @max_attempts = Integer(max_attempts)
        @sleep = sleep
        @random = random
        @http_client = http_client
      end
      # rubocop:enable Metrics/ParameterLists

      # @return [Hash] +:content+ (assistant text), +:stop_reason+, +:usage+ (symbol keys)
      def chat(messages:, system: nil, max_tokens: 8192)
        payload = build_body(messages: messages, system: system, max_tokens: max_tokens, stream: false)
        response = perform_request(payload)
        raise AnthropicAPIError, error_message_for(response) unless response.code == "200"

        parse_success_response(response.body)
      end

      # Streams message deltas (SSE). Yields hashes +{ delta:, stop_reason: }+ (symbols).
      def stream_chat(messages:, system: nil, max_tokens: 8192, &block)
        raise ArgumentError, "stream_chat requires a block" unless block

        payload = build_body(messages: messages, system: system, max_tokens: max_tokens, stream: true)
        perform_stream_request(payload, &block)
      end

      private

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- small retry loop
      def perform_request(payload)
        uri = URI(API_URL)
        last_response = nil
        @max_attempts.times do |attempt|
          http = open_http(uri)
          last_response = http.request(build_post(uri, payload))
          code = Integer(last_response.code)
          return last_response if code == 200
          raise AnthropicAPIError, error_message_for(last_response) unless retryable_status?(code)
          raise AnthropicAPIError, error_message_for(last_response) if attempt >= @max_attempts - 1

          sleep_for_retry!(attempt, last_response)
        end
        last_response
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT => e
        raise AnthropicAPIError, "HTTP timeout: #{e.class}: #{e.message}"
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      # rubocop:disable Metrics/MethodLength -- small retry loop around streaming body
      def perform_stream_request(payload, &block)
        uri = URI(API_URL)
        finished = false
        @max_attempts.times do |attempt|
          break if finished

          http = open_http(uri)
          http.request(build_post(uri, payload)) do |response|
            code = Integer(response.code)
            if code == 200
              consume_sse_stream(response, &block)
              finished = true
            else
              handle_stream_error_response!(response, attempt, code)
            end
          end
        end

        nil
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT => e
        raise AnthropicAPIError, "HTTP timeout: #{e.class}: #{e.message}"
      end
      # rubocop:enable Metrics/MethodLength

      def handle_stream_error_response!(response, attempt, code)
        err_body = drain_response_body(response)
        unless retryable_status?(code) && attempt < @max_attempts - 1
          raise AnthropicAPIError, "Anthropic API status=#{response.code} body=#{err_body}"
        end

        sleep_for_retry!(attempt, response)
      end

      def drain_response_body(response)
        buf = +""
        response.read_body { |frag| buf << frag } if response.respond_to?(:read_body)
        buf
      rescue StandardError
        ""
      end

      def consume_sse_stream(response, &)
        buffer = +""
        response.read_body do |fragment|
          buffer << fragment
          while (idx = buffer.index("\n"))
            line = buffer.slice!(0..idx).chomp
            handle_sse_line(line, &)
          end
        end
        handle_sse_line(buffer, &) unless buffer.to_s.strip.empty?
      end

      def handle_sse_line(line, &)
        return if line.strip.empty?
        return unless line.start_with?("data:")

        payload = line.sub(/\Adata:\s*/, "").strip
        return if payload == "[DONE]"

        data = JSON.parse(payload)
        emit_stream_json!(data, &)
      rescue JSON::ParserError
        nil
      end

      def emit_stream_json!(data, &)
        case data["type"]
        when "content_block_delta"
          inner = data["delta"]
          yield(delta: inner["text"].to_s, stop_reason: nil) if text_delta?(inner)
        when "message_delta"
          inner = data["delta"]
          yield(delta: "", stop_reason: inner["stop_reason"]) if inner.is_a?(Hash) && inner["stop_reason"]
        end
      end

      def text_delta?(inner)
        inner.is_a?(Hash) && inner["type"] == "text_delta"
      end

      def retryable_status?(code)
        RETRYABLE_STATUSES.include?(code)
      end

      def sleep_for_retry!(attempt, response)
        header_secs = parse_retry_after_seconds(response)
        base = DEFAULT_BASE_DELAY * (BACKOFF_FACTOR**attempt)
        jittered = base * jitter_multiplier
        delay = header_secs.nil? ? jittered : header_secs
        @sleep.call([delay, 0.0].max)
      end

      def jitter_multiplier
        span = JITTER_HIGH - JITTER_LOW
        JITTER_LOW + (@random.rand * span)
      end

      def parse_retry_after_seconds(response)
        raw = response["retry-after"]
        return nil if raw.nil? || raw.to_s.strip.empty?

        Integer(raw)
      rescue ArgumentError, TypeError
        nil
      end

      def build_body(messages:, system:, max_tokens:, stream:)
        payload = {
          "model" => @model,
          "max_tokens" => Integer(max_tokens),
          "messages" => normalize_messages(messages),
          "stream" => stream
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

      def open_http(uri)
        http = @http_client.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = @open_timeout
        http.read_timeout = @request_timeout
        http
      end

      def build_post(uri, payload)
        req = Net::HTTP::Post.new(uri.request_uri)
        req["x-api-key"] = @api_key
        req["anthropic-version"] = ANTHROPIC_VERSION
        req["content-type"] = "application/json"
        req["accept"] = "application/json"
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
    # rubocop:enable Metrics/ClassLength
  end
end

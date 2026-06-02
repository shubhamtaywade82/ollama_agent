# frozen_string_literal: true

require_relative "base"

module OllamaAgent
  module Providers
    # Ollama provider — wraps the existing ollama-client gem.
    #
    # Supports two modes:
    #
    #   Local Ollama (default)
    #     host:    "http://localhost:11434"  (or OLLAMA_HOST)
    #     api_key: nil
    #
    #   Ollama Cloud
    #     host:    "https://api.ollama.com"  (or OLLAMA_BASE_URL)
    #     api_key: "ollama_..."               (or OLLAMA_API_KEY)
    #
    # When api_key is provided the key is injected into Ollama::Config so every
    # request carries +Authorization: Bearer <key>+. This is how multi-key
    # Ollama Cloud credential pools work — each Credential supplies its own key.
    class Ollama < Base
      CLOUD_HOST      = "https://api.ollama.com"
      LOCAL_HOST      = "http://localhost:11434"
      DEFAULT_TIMEOUT = 120

      def initialize(host: nil, api_key: nil, timeout: nil, **)
        super(name: "ollama", **)
        @api_key = api_key || ENV.fetch("OLLAMA_API_KEY", nil)
        @host    = host    || ENV.fetch("OLLAMA_BASE_URL", nil) ||
                   ENV.fetch("OLLAMA_HOST", LOCAL_HOST)
        @timeout = timeout || DEFAULT_TIMEOUT
      end

      # @param messages [Array<Hash>]
      # @param model    [String]
      # @param tools    [Array<Hash>]
      # @param stream_hooks [Hash] :on_token, :on_thinking lambdas
      # @param temperature [Float]
      # @param think [String, nil]
      # @return [Response]
      def chat(messages:, model:, tools: nil, stream_hooks: nil, temperature: 0.2, think: nil, **_opts)
        require "ollama_client"

        client = build_client
        req    = build_request(messages: messages, model: model, tools: tools,
                               temperature: temperature, think: think)

        raw = if stream_hooks
                client.chat(**req, hooks: stream_hooks)
              else
                client.chat(**req)
              end

        build_response(raw, model)
      end

      def available?
        require "net/http"
        # For Ollama Cloud, check by hitting the tags endpoint with the key
        uri = URI("#{@host}/api/tags")
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{@api_key}" if @api_key
        resp = Net::HTTP.start(uri.host, uri.port,
                               use_ssl: uri.scheme == "https",
                               open_timeout: 5, read_timeout: 10) { |h| h.request(req) }
        resp.is_a?(Net::HTTPSuccess)
      rescue StandardError
        false
      end

      def streaming_supported?
        true
      end

      # True when this credential is configured for Ollama Cloud (has an api_key).
      def cloud?
        @api_key && !@api_key.to_s.strip.empty?
      end

      # Performs a pre-flight check using the /api/show endpoint.
      # @param model [String]
      # @return [Boolean] true if the model specifically requires a subscription
      def subscription_required?(model)
        return false unless cloud?

        require "net/http"
        require "json"

        uri = URI("#{@host}/api/show")
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{@api_key}" if @api_key
        req.body = { name: model }.to_json
        req.content_type = "application/json"

        resp = Net::HTTP.start(uri.host, uri.port,
                               use_ssl: uri.scheme == "https",
                               open_timeout: 5, read_timeout: 10) { |h| h.request(req) }

        # Ollama Cloud returns 403 with a "subscription required" message for gated models.
        resp.code == "403" && resp.body.to_s.match?(/subscription/i)
      rescue StandardError
        false
      end

      private

      def build_client
        require_relative "../ollama_connection"

        OllamaAgent::OllamaConnection.retry_wrapped_client(
          timeout: @timeout,
          max_attempts: options.fetch(:max_retries, 3),
          base_url: @host,
          api_key: @api_key,
          hooks: nil
        )
      end

      def build_request(messages:, model:, tools:, temperature:, think:)
        req = {
          messages: messages,
          model: model,
          options: { temperature: temperature }
        }
        req[:tools] = tools if tools && !tools.empty?
        req[:think] = think if think
        req
      end

      def build_response(raw, model)
        msg = raw.message
        raise OllamaAgent::Error, "Empty response from Ollama" if msg.nil?

        message = {
          role: msg.role,
          content: msg.content,
          tool_calls: normalize_tool_calls(msg.tool_calls)
        }

        usage = extract_usage(raw)
        Response.new(message: message, usage: usage, provider: "ollama", model: model)
      rescue OllamaAgent::Error
        raise
      rescue StandardError => e
        msg = e.message.to_s
        # Map Ollama Cloud HTTP errors into the typed hierarchy
        raise OllamaAgent::SubscriptionRequiredError, msg if msg.match?(/\b403\b/) && msg.match?(/subscription/i)

        raise OllamaAgent::AuthenticationError, msg if msg.match?(/\b(401|403)\b/)
        raise OllamaAgent::RateLimitError, msg       if msg.match?(/\b429\b/) &&
                                                        !msg.downcase.match?(/quota|limit/)
        raise OllamaAgent::QuotaExhaustedError, msg  if msg.match?(/\b429\b/)
        raise OllamaAgent::TemporaryProviderError, msg if msg.match?(/\b5\d{2}\b/)

        raise
      end

      def normalize_tool_calls(calls)
        return [] unless calls.respond_to?(:map)

        calls.map do |tc|
          fn = tc.respond_to?(:function) ? tc.function : tc[:function]
          {
            id: tc.respond_to?(:id) ? tc.id : tc[:id],
            type: "function",
            function: { name: fn.name, arguments: fn.arguments }
          }
        end
      end

      def extract_usage(raw)
        return nil unless raw.respond_to?(:eval_count)

        {
          prompt_tokens: raw.respond_to?(:prompt_eval_count) ? raw.prompt_eval_count.to_i : 0,
          completion_tokens: raw.eval_count.to_i,
          total_tokens: (raw.respond_to?(:prompt_eval_count) ? raw.prompt_eval_count.to_i : 0) +
            raw.eval_count.to_i
        }
      end
    end
  end
end

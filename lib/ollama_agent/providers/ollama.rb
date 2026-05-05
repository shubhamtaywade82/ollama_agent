# frozen_string_literal: true

require_relative "base"

module OllamaAgent
  module Providers
    # Ollama provider — wraps the existing ollama-client gem.
    # This is the default provider; all existing Agent behaviour is preserved.
    class Ollama < Base
      DEFAULT_MODEL   = "llama3.2"
      DEFAULT_TIMEOUT = 120

      def initialize(host: nil, timeout: nil, **)
        super(name: "ollama", **)
        @host    = host    || ENV.fetch("OLLAMA_HOST", "http://localhost:11434")
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
        uri = URI("#{@host}/api/tags")
        Net::HTTP.get_response(uri).is_a?(Net::HTTPSuccess)
      rescue StandardError
        false
      end

      def streaming_supported?
        true
      end

      private

      def build_client
        require_relative "../ollama_connection"

        OllamaAgent::OllamaConnection.retry_wrapped_client(
          timeout: @timeout,
          max_attempts: options.fetch(:max_retries, 3),
          base_url: @host,
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

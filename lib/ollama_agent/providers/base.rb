# frozen_string_literal: true

# Ensure base error classes exist even when providers are required standalone.
module OllamaAgent
  unless defined?(Error)
    class Error < StandardError
    end
  end
  unless defined?(ConfigurationError)
    class ConfigurationError < Error
    end
  end
end

module OllamaAgent
  module Providers
    # Abstract base class for model providers.
    #
    # Every provider must implement:
    #   #chat(messages:, model:, tools: nil, stream_hooks: nil, **opts) → Response
    #   #available? → Boolean
    #
    # A Response must respond to:
    #   #message    → { role:, content:, tool_calls: }
    #   #usage      → { prompt_tokens:, completion_tokens:, total_tokens: } or nil
    class Base
      # Unified response wrapper returned by all providers.
      Response = Data.define(:message, :usage, :provider, :model) do
        def total_tokens
          usage&.fetch(:total_tokens, 0) || 0
        end

        def tool_calls
          message&.fetch(:tool_calls, nil) || []
        end

        def content
          message&.fetch(:content, nil)
        end
      end

      attr_reader :name

      def initialize(name:, **options)
        @name    = name.to_s
        @options = options
      end

      # @abstract
      # @param messages [Array<Hash>] conversation history
      # @param model    [String]      model identifier
      # @param tools    [Array<Hash>] tool schemas (nil = no tools)
      # @param stream_hooks [Hash]   optional :on_token, :on_thinking lambdas
      # @return [Response]
      def chat(messages:, model:, tools: nil, stream_hooks: nil, **opts)
        raise NotImplementedError, "#{self.class}#chat is not implemented"
      end

      # @abstract
      # @return [Boolean] true when the provider can accept requests right now
      def available?
        raise NotImplementedError, "#{self.class}#available? is not implemented"
      end

      # Override in subclasses that support streaming natively.
      def streaming_supported?
        false
      end

      # Returns approximate cost in USD for the given token counts.
      # Subclasses may override with provider-specific pricing.
      def estimate_cost(input_tokens:, output_tokens:)
        0.0
      end

      def to_s
        "#<#{self.class.name} name=#{@name}>"
      end

      protected

      attr_reader :options
    end
  end
end

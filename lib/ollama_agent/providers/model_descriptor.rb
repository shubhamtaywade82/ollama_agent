# frozen_string_literal: true

module OllamaAgent
  module Providers
    # Represents properties, limits, and capabilities of an LLM.
    class ModelDescriptor
      attr_reader :name, :provider, :context_size, :capabilities, :size_gb, :status

      def initialize(name:, provider:, context_size: 8192, capabilities: [:chat],
                     size_gb: nil, status: "available", subscription_required: false)
        @name         = name.to_s
        @provider     = provider.to_s
        @context_size = context_size.to_i
        @capabilities = Array(capabilities).map(&:to_sym)
        @size_gb      = size_gb ? size_gb.to_f : nil
        @status       = status.to_s
        @subscription_required = subscription_required
      end

      def tools?
        @capabilities.include?(:tools)
      end

      def vision?
        @capabilities.include?(:vision)
      end

      def reasoning?
        @capabilities.include?(:reasoning)
      end

      def subscription_required?
        @subscription_required
      end

      def to_s
        "#<#{self.class.name} name=#{@name} provider=#{@provider} context=#{@context_size} caps=#{@capabilities.inspect}>"
      end
    end
  end
end

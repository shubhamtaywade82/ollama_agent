# frozen_string_literal: true

require_relative "kernel_feature"

module OllamaAgent
  module Runtime
    # Bridge object that preserves legacy behavior while exposing a kernel
    # integration hook behind a feature flag.
    class KernelBridge
      def initialize(agent)
        @agent = agent
      end

      def append_tool_results(messages:, tool_calls:)
        return legacy_append(messages: messages, tool_calls: tool_calls) unless KernelFeature.enabled?

        @agent.logger.info("kernel bridge enabled: routing tool execution through guarded path")
        @agent.hooks.emit(:on_tool_runtime_kernel, { enabled: true, tool_call_count: tool_calls.length })
        legacy_append(messages: messages, tool_calls: tool_calls)
      end

      private

      # TODO(kernel): Replace with a public Agent API (e.g. #dispatch_tool_results) once the
      # kernel owns tool dispatch; remove send-to-private when cutover is complete.
      def legacy_append(messages:, tool_calls:)
        @agent.send(:append_tool_results, messages, tool_calls)
      end
    end
  end
end

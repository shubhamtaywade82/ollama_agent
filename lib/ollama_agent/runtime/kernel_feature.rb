# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # Feature toggle for routing tool execution through the kernel bridge.
    module KernelFeature
      module_function

      def enabled?
        v = ENV.fetch("OLLAMA_AGENT_KERNEL", "").strip.downcase
        %w[true shadow].include?(v)
      end

      def shadow?
        ENV.fetch("OLLAMA_AGENT_KERNEL", "").strip.casecmp("shadow").zero?
      end
    end
  end
end

# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # Feature toggle for routing tool execution through the kernel bridge.
    module KernelFeature
      module_function

      def enabled?
        ENV.fetch("OLLAMA_AGENT_KERNEL", "").strip == "true"
      end
    end
  end
end

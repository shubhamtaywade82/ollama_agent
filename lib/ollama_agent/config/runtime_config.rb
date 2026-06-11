# frozen_string_literal: true

module OllamaAgent
  module Config
    class RuntimeConfig
      attr_reader :confirm_patches, :read_only, :patch_policy, :system_prompt,
                  :http_timeout, :think, :orchestrator, :confirm_delegation,
                  :max_retries, :audit, :provider, :provider_name

      def initialize(confirm_patches: true, read_only: false, patch_policy: nil,
                     system_prompt: nil, http_timeout: nil, think: nil,
                     orchestrator: false, confirm_delegation: nil,
                     max_retries: nil, audit: nil, provider: nil, provider_name: nil)
        @confirm_patches = confirm_patches
        @read_only = read_only
        @patch_policy = patch_policy
        @system_prompt = system_prompt
        @http_timeout = http_timeout
        @think = think
        @orchestrator = orchestrator
        @confirm_delegation = confirm_delegation
        @max_retries = max_retries
        @audit = audit
        @provider = provider
        @provider_name = provider_name
      end

      def resolved_confirm_delegation
        @confirm_delegation.nil? || @confirm_delegation
      end
    end
  end
end
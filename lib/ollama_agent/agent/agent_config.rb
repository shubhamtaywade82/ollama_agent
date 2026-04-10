# frozen_string_literal: true

module OllamaAgent
  class Agent
    # Value object grouping Agent construction options (Runner and tests build this explicitly).
    class AgentConfig
      attr_reader :model, :root, :confirm_patches, :http_timeout, :think, :read_only, :patch_policy,
                  :skill_paths, :skills_enabled, :skills_include, :skills_exclude, :external_skills_enabled,
                  :orchestrator, :confirm_delegation, :max_retries, :audit, :session_id, :resume,
                  :max_tokens, :context_summarize, :stdin, :stdout

      # @param confirm_delegation [Boolean, nil] nil means default true
      # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists, Metrics/AbcSize -- value object mirrors Agent keywords
      def initialize(model: nil, root: nil, confirm_patches: true, http_timeout: nil, think: nil,
                     read_only: false, patch_policy: nil,
                     skill_paths: nil, skills_enabled: nil, skills_include: nil, skills_exclude: nil,
                     external_skills_enabled: nil,
                     orchestrator: false, confirm_delegation: nil,
                     max_retries: nil, audit: nil,
                     session_id: nil, resume: false,
                     max_tokens: nil, context_summarize: nil,
                     stdin: $stdin, stdout: $stdout)
        @model = model
        @root = root
        @confirm_patches = confirm_patches
        @http_timeout = http_timeout
        @think = think
        @read_only = read_only
        @patch_policy = patch_policy
        @skill_paths = skill_paths
        @skills_enabled = skills_enabled
        @skills_include = skills_include
        @skills_exclude = skills_exclude
        @external_skills_enabled = external_skills_enabled
        @orchestrator = orchestrator
        @confirm_delegation = confirm_delegation
        @max_retries = max_retries
        @audit = audit
        @session_id = session_id
        @resume = resume
        @max_tokens = max_tokens
        @context_summarize = context_summarize
        @stdin = stdin
        @stdout = stdout
      end
      # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists, Metrics/AbcSize

      def resolved_confirm_delegation
        @confirm_delegation.nil? || @confirm_delegation
      end
    end
  end
end

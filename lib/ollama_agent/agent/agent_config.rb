# frozen_string_literal: true

module OllamaAgent
  class Agent
    # Value object grouping Agent construction options (Runner and tests build this explicitly).
    class AgentConfig
      attr_reader :model, :root, :confirm_patches, :http_timeout, :think, :read_only, :patch_policy,
                  :system_prompt,
                  :skill_paths, :skills_enabled, :skills_include, :skills_exclude, :external_skills_enabled,
                  :orchestrator, :confirm_delegation, :max_retries, :audit, :session_id, :resume,
                  :max_tokens, :context_summarize, :stdin, :stdout, :user_prompt, :logger,
                  # v2 platform options
                  :provider, :provider_name, :budget, :permissions, :policies,
                  :memory_manager, :trace_logger, :approval_gate

      # @param confirm_delegation [Boolean, nil] nil means default true
      # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists, Metrics/AbcSize -- value object mirrors Agent keywords
      def initialize(model: nil, root: nil, confirm_patches: true, http_timeout: nil, think: nil,
                     read_only: false, patch_policy: nil,
                     system_prompt: nil,
                     skill_paths: nil, skills_enabled: nil, skills_include: nil, skills_exclude: nil,
                     external_skills_enabled: nil,
                     orchestrator: false, confirm_delegation: nil,
                     max_retries: nil, audit: nil,
                     session_id: nil, resume: false,
                     max_tokens: nil, context_summarize: nil,
                     stdin: $stdin, stdout: $stdout, user_prompt: nil, logger: nil,
                     # v2 platform options (all optional — nil keeps existing behaviour)
                     provider: nil, provider_name: nil, budget: nil,
                     permissions: nil, policies: nil,
                     memory_manager: nil, trace_logger: nil, approval_gate: nil)
        @model = model
        @root = root

        # Compose sub-configs
        @runtime = Config::RuntimeConfig.new(
          confirm_patches: confirm_patches,
          read_only: read_only,
          patch_policy: patch_policy,
          system_prompt: system_prompt,
          http_timeout: http_timeout,
          think: think,
          orchestrator: orchestrator,
          confirm_delegation: confirm_delegation,
          max_retries: max_retries,
          audit: audit,
          provider: provider,
          provider_name: provider_name
        )

        @skills = Config::SkillConfig.new(
          skill_paths: skill_paths,
          skills_enabled: skills_enabled,
          skills_include: skills_include,
          skills_exclude: skills_exclude,
          external_skills_enabled: external_skills_enabled
        )

        @session = Config::SessionConfig.new(
          session_id: session_id,
          resume: resume,
          max_tokens: max_tokens,
          context_summarize: context_summarize,
          stdin: stdin,
          stdout: stdout,
          user_prompt: user_prompt,
          logger: logger
        )

        # v2 platform options stored directly on AgentConfig
        @provider       = provider
        @provider_name  = provider_name
        @budget         = budget
        @permissions    = permissions
        @policies       = policies
        @memory_manager = memory_manager
        @trace_logger   = trace_logger
        @approval_gate  = approval_gate
      end
      # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists, Metrics/AbcSize

      # Backward-compat delegation to sub-configs
      def runtime = @runtime
      def skills = @skills
      def session = @session

      def confirm_patches = @runtime.confirm_patches
      def http_timeout = @runtime.http_timeout
      def think = @runtime.think
      def read_only = @runtime.read_only
      def patch_policy = @runtime.patch_policy
      def system_prompt = @runtime.system_prompt
      def orchestrator = @runtime.orchestrator
      def confirm_delegation = @runtime.resolved_confirm_delegation
      def max_retries = @runtime.max_retries
      def audit = @runtime.audit

      def skill_paths = @skills.skill_paths
      def skills_enabled = @skills.skills_enabled
      def skills_include = @skills.skills_include
      def skills_exclude = @skills.skills_exclude
      def external_skills_enabled = @skills.external_skills_enabled

      def session_id = @session.session_id
      def resume = @session.resume
      def max_tokens = @session.max_tokens
      def context_summarize = @session.context_summarize
      def stdin = @session.stdin
      def stdout = @session.stdout
      def user_prompt = @session.user_prompt
      def logger = @session.logger

      def resolved_confirm_delegation
        @runtime.resolved_confirm_delegation
      end
    end
  end
end

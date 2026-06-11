# frozen_string_literal: true

require "logger"

require_relative "agent_prompt"
require_relative "prompt_skills"
require_relative "console"
require_relative "ollama_connection"
require_relative "tools_schema"
require_relative "sandboxed_tools"
require_relative "think_param"
require_relative "gemma_thought_content_parser"
require_relative "timeout_param"
require_relative "tool_content_parser"
require_relative "streaming/hooks"
require_relative "resilience/retry_middleware"
require_relative "resilience/audit_logger"
require_relative "context/manager"
require_relative "session/store"
require_relative "env_config"
require_relative "model_env"
require_relative "ollama_cloud_catalog"
require_relative "agent_root_resolver"
require_relative "agent/agent_config"
require_relative "client_manager"
require_relative "prompt_builder"
require_relative "model_manager"
require_relative "agent/client_wiring"
require_relative "agent/prompt_wiring"
require_relative "agent/session_wiring"
require_relative "agent/chat_coordinator"
require_relative "agent/turn_loop"
require_relative "core/budget"
require_relative "core/loop_detector"
require_relative "core/trace_logger"

module OllamaAgent
  # Runs a tool-calling loop against Ollama: read files, search, apply unified diffs.
  # Public entry: {#run}. Other instance methods are internal to the agent loop.
  # rubocop:disable Metrics/ClassLength -- facade coordinates includes, config, and chat helpers
  class Agent
    include SandboxedTools
    include ClientWiring
    include PromptWiring
    include SessionWiring

    MAX_TURNS = 64
    DEFAULT_HTTP_TIMEOUT = 120

    attr_accessor :client
    attr_reader :config
    attr_reader :root, :hooks, :model, :logger, :policies

    # Backward-compat attr_reader shims delegating to config
    def read_only = @config.runtime.read_only
    def max_tokens = @config.session.max_tokens
    def orchestrator = @config.runtime.orchestrator
    def provider_name
      # Keep @provider_name ivar for backward compat with tests using instance_variable_get
      @provider_name ||= @config.runtime.provider_name
    end
    def session_id = @config.session.session_id

    # Backward-compat: expose as attr_reader for tests using instance_variable_get
    attr_reader :permissions

    # @param config [AgentConfig, nil] when set, keyword options are ignored (use {Runner} or build {AgentConfig}).
    # rubocop:disable Metrics/ParameterLists
    # rubocop:disable Metrics/MethodLength
    def initialize(client: nil, config: nil, model: nil, root: nil, confirm_patches: true, http_timeout: nil,
                   think: nil,
                   read_only: false, patch_policy: nil,
                   system_prompt: nil,
                   skill_paths: nil, skills_enabled: nil, skills_include: nil, skills_exclude: nil,
                   external_skills_enabled: nil,
                   orchestrator: false, confirm_delegation: nil,
                   max_retries: nil, audit: nil,
                   session_id: nil, resume: false,
                   max_tokens: nil, context_summarize: nil,
                   stdin: $stdin, stdout: $stdout,
                   provider: nil, provider_name: nil, budget: nil,
                   permissions: nil, policies: nil,
                   memory_manager: nil, trace_logger: nil, approval_gate: nil, user_prompt: nil,
                   logger: nil)
      cfg = config || AgentConfig.new(
        model: model, root: root, confirm_patches: confirm_patches, http_timeout: http_timeout, think: think,
        read_only: read_only, patch_policy: patch_policy,
        system_prompt: system_prompt,
        skill_paths: skill_paths, skills_enabled: skills_enabled, skills_include: skills_include,
        skills_exclude: skills_exclude, external_skills_enabled: external_skills_enabled,
        orchestrator: orchestrator, confirm_delegation: confirm_delegation,
        max_retries: max_retries, audit: audit, session_id: session_id, resume: resume,
        max_tokens: max_tokens, context_summarize: context_summarize, stdin: stdin, stdout: stdout,
        provider: provider, provider_name: provider_name, budget: budget,
        permissions: permissions, policies: policies,
        memory_manager: memory_manager, trace_logger: trace_logger, approval_gate: approval_gate,
        user_prompt: user_prompt,
        logger: logger
      )
      @config = cfg
      @model = cfg.model || default_model
      @root = AgentRootResolver.resolve(cfg.root)
      @logger = cfg.session.logger || build_default_logger
      @hooks = Streaming::Hooks.new

      # Collaborators initialized after @hooks is available
      @client_manager = ClientManager.new(config: @config, hooks: @hooks)
      @prompt_builder = PromptBuilder.new(config: @config)

      # Ivars for SandboxedTools backward compat (module accesses @root, @read_only, @confirm_patches, @patch_policy)
      @confirm_patches = cfg.confirm_patches
      @read_only = cfg.read_only
      @patch_policy = cfg.patch_policy

      # Keep @provider_name and @permissions as ivars for backward compat with tests using instance_variable_get
      @provider_name = cfg.provider_name
      @permissions = cfg.permissions

      @user_prompt = cfg.user_prompt || UserPrompt.new(stdin: cfg.stdin, stdout: cfg.stdout)
      @context_manager = Context::Manager.new(max_tokens: cfg.session.max_tokens, context_summarize: cfg.session.context_summarize)

      strict = EnvConfig.strict_env?
      @max_turns = EnvConfig.fetch_int("OLLAMA_AGENT_MAX_TURNS", MAX_TURNS, strict: strict)
      @budget = cfg.budget || Core::Budget.new(max_steps: @max_turns, max_tokens: cfg.session.max_tokens)
      @loop_detector = Core::LoopDetector.new
      @trace_logger = cfg.trace_logger
      @memory_manager = cfg.memory_manager
      @policies = cfg.policies
      @approval_gate = cfg.approval_gate

      @toolbox = Toolbox.new(config: @config, logger: @logger)
      @session_manager = SessionManager.new(
        config: @config,
        hooks: @hooks,
        toolbox: @toolbox,
        loop_detector: @loop_detector,
        trace_logger: @trace_logger,
        budget: @budget,
        permissions: @permissions,
        policies: @policies,
        memory_manager: @memory_manager
      )

      @chat_coordinator = ChatCoordinator.new(
        client: nil, # will be set after client is initialized
        model_manager: nil, # will be set after model_manager is initialized
        config: @config,
        hooks: @hooks
      )
      @kernel_bridge = Runtime::KernelBridge.new(
        session_manager: @session_manager,
        toolbox: @toolbox,
        hooks: @hooks,
        loop_detector: @loop_detector,
        memory_manager: @memory_manager,
        config: @config,
        logger: @logger,
        permissions: @permissions,
        policies: @policies
      )

      attach_audit_logger if resolved_audit_enabled
      @client = client || @client_manager.build_default_client
      @model_manager = ModelManager.new(client: @client, default_model: @model)
      @model = @model_manager.model

      # Update chat_coordinator with actual client and model_manager now that they exist
      @chat_coordinator.instance_variable_set(:@client, @client)
      @chat_coordinator.instance_variable_set(:@model_manager, @model_manager)
    end
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/ParameterLists

    # Model access delegated to ModelManager
    def model = @model_manager.model

    def assign_chat_model!(name) = @model_manager.assign_chat_model!(name)
    def model_accessible?(name = nil) = @model_manager.model_accessible?(name)
    def list_local_model_names = @model_manager.list_local_model_names
    def list_cloud_model_names = @model_manager.list_cloud_model_names

    def run(query)
      messages = build_messages_for_run(query)
      TurnLoop.new(
        max_turns: @max_turns,
        budget: @budget,
        loop_detector: @loop_detector,
        trace_logger: @trace_logger,
        context_manager: @context_manager,
        chat_coordinator: @chat_coordinator,
        hooks: @hooks,
        logger: @logger,
        kernel_bridge: @kernel_bridge,
        session_manager: @session_manager
      ).run(messages)
    end

    # Subclasses that override chat or tool wiring should keep {#assign_chat_model!} in sync
    # if they depend on +@model+ matching the HTTP client catalog.

    private

    def build_default_logger
      Logger.new($stderr, progname: "ollama_agent").tap do |log|
        log.level = logger_level_from_env
      end
    end

    def logger_level_from_env
      case ENV.fetch("OLLAMA_AGENT_LOG_LEVEL", "").strip.downcase
      when "debug" then Logger::DEBUG
      when "info" then Logger::INFO
      when "warn" then Logger::WARN
      when "error" then Logger::ERROR
      else
        ENV["OLLAMA_AGENT_DEBUG"] == "1" ? Logger::DEBUG : Logger::WARN
      end
    end

    def chat_request_args(messages)
      @chat_coordinator.request_args(messages)
    end

    def default_model
      ModelEnv.default_chat_model
    end
  end
  # rubocop:enable Metrics/ClassLength
end
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
    attr_reader :root, :hooks, :model, :logger,
                :session_id, :read_only, :max_tokens, :orchestrator, :provider_name

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
      apply_agent_config(cfg)
      @user_prompt = cfg.user_prompt || UserPrompt.new(stdin: cfg.stdin, stdout: cfg.stdout)
      @context_manager = Context::Manager.new(max_tokens: @max_tokens, context_summarize: @context_summarize)
      @hooks = Streaming::Hooks.new
      attach_audit_logger if resolved_audit_enabled
      @client = client || build_default_client
    end
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/ParameterLists

    def run(query)
      Console.reset_thinking_session!
      messages = build_messages_for_run(query)
      TurnLoop.new(self).run(messages)
    end

    # Switch the chat model for subsequent {#run} calls (same session, same client).
    # Accepts Ollama local tags (e.g. +llama3.2+) or cloud catalog names (e.g. +glm-5.1+).
    #
    # @param name [String]
    # @return [String] the normalized model id
    # @raise [OllamaAgent::EmptyModelNameError] when +name+ is blank
    def assign_chat_model!(name)
      n = name.to_s.strip
      raise EmptyModelNameError, "Model name cannot be empty" if n.empty?

      @model = n
      n
    end

    # Performs a pre-flight check to see if the model is accessible.
    # Currently only implemented for Ollama Cloud (checks for 403 Subscription Required).
    #
    # @param name [String, nil] defaults to current @model
    # @return [Boolean] true if accessible or check not applicable
    def model_accessible?(name = nil)
      n = name || @model
      return true unless @client.respond_to?(:cloud?) && @client.cloud?
      return true unless @client.respond_to?(:subscription_required?)

      !@client.subscription_required?(n)
    rescue StandardError
      true # assume accessible if check fails
    end

    # Names from the local Ollama daemon (+/api/tags+ on your +base_url+). Not used by the REPL +/models+ command.
    #
    # @return [Array<String>]
    def list_local_model_names
      return [] unless @client.respond_to?(:list_model_names)

      @client.list_model_names
    rescue StandardError => e
      logger.warn("list_local_model_names failed (#{e.class}: #{e.message})")
      logger.debug(e.full_message) if ENV["OLLAMA_AGENT_DEBUG"] == "1"
      []
    end

    def list_cloud_model_names
      base_url = nil
      api_key = nil

      if @client.respond_to?(:client) && @client.client.respond_to?(:config)
        config = @client.client.config
        base_url = config.base_url
        api_key = config.api_key
      end

      # Fallback to OLLAMA_BASE_URL if client doesn't expose it
      base_url ||= ENV.fetch("OLLAMA_BASE_URL", nil)

      # If it's a cloud-like URL, we can try to append /api/tags if needed,
      # but OllamaCloudCatalog.list_model_names handles the mapping.
      catalog_host = base_url ? "#{base_url.to_s.chomp("/")}/api/tags" : nil

      OllamaCloudCatalog.list_model_names(base_url: catalog_host, api_key: api_key)
    end

    # Subclasses that override chat or tool wiring should keep {#assign_chat_model!} in sync
    # if they depend on +@model+ matching the HTTP client catalog.

    private

    def chat_coordinator
      @chat_coordinator ||= ChatCoordinator.new(self)
    end

    def apply_agent_config(cfg)
      assign_model_and_root!(cfg)
      assign_runtime_flags!(cfg)
      assign_skill_options!(cfg)
      assign_session_and_limits!(cfg)
      assign_platform_subsystems!(cfg)
    end

    def assign_model_and_root!(cfg)
      @model = cfg.model || default_model
      @root = AgentRootResolver.resolve(cfg.root)
      @logger = cfg.logger || build_default_logger
    end

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

    # rubocop:disable Metrics/MethodLength -- one-line ivar copies from AgentConfig
    def assign_runtime_flags!(cfg)
      @confirm_patches = cfg.confirm_patches
      @read_only = cfg.read_only
      @patch_policy = cfg.patch_policy
      @system_prompt = cfg.system_prompt
      @http_timeout_override = cfg.http_timeout
      @think = cfg.think
      @orchestrator = cfg.orchestrator
      @confirm_delegation = cfg.resolved_confirm_delegation
      @max_retries = cfg.max_retries
      @audit = cfg.audit
      @provider = cfg.provider
      @provider_name = cfg.provider_name
    end
    # rubocop:enable Metrics/MethodLength

    def assign_skill_options!(cfg)
      @skill_paths = cfg.skill_paths
      @skills_enabled = cfg.skills_enabled
      @skills_include = cfg.skills_include
      @skills_exclude = cfg.skills_exclude
      @external_skills_enabled = cfg.external_skills_enabled
    end

    def assign_session_and_limits!(cfg)
      @session_id = cfg.session_id
      @resume = cfg.resume
      @max_tokens = cfg.max_tokens
      @context_summarize = cfg.context_summarize
      strict = EnvConfig.strict_env?
      @max_turns = EnvConfig.fetch_int("OLLAMA_AGENT_MAX_TURNS", MAX_TURNS, strict: strict)
    end

    def assign_platform_subsystems!(cfg)
      @budget        = cfg.budget || Core::Budget.new(max_steps: @max_turns, max_tokens: @max_tokens)
      @loop_detector = Core::LoopDetector.new
      @trace_logger  = cfg.trace_logger
      @memory_manager = cfg.memory_manager
      @permissions   = cfg.permissions
      @policies      = cfg.policies
      @approval_gate = cfg.approval_gate
    end

    def trimmed_messages_for_chat(messages)
      @context_manager.trim(messages)
    end

    def persist_assistant_turn(messages, message)
      messages << message.to_h
      save_message_to_session(message.to_h)
    end

    def emit_turn_complete(messages)
      @hooks.emit(:on_complete, { messages: messages, turns: @current_turn })
    end

    def warn_max_turns_if_needed
      return unless ENV["OLLAMA_AGENT_DEBUG"] == "1" && @current_turn >= @max_turns

      logger.warn("maximum tool rounds (#{@max_turns}) reached")
    end

    def current_turn
      @current_turn || 0
    end

    def tool_calls_from(message)
      calls = message.tool_calls || []
      return calls unless calls.empty? && ToolContentParser.enabled?

      ToolContentParser.synthetic_calls(message.content)
    end

    def chat_request_args(messages)
      chat_coordinator.request_args(messages)
    end

    def resolve_think
      ThinkParam.resolve(@think)
    end

    def default_model
      ModelEnv.default_chat_model
    end
  end
  # rubocop:enable Metrics/ClassLength
end

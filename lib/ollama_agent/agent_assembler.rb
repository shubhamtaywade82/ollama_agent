# frozen_string_literal: true

require "logger"
require_relative "agent"
require_relative "agent/agent_config"
require_relative "client_manager"
require_relative "prompt_builder"
require_relative "model_manager"
require_relative "session_manager"
require_relative "toolbox"
require_relative "streaming/hooks"
require_relative "context/manager"
require_relative "user_prompt"
require_relative "core/budget"
require_relative "core/loop_detector"
require_relative "agent/chat_coordinator"
require_relative "runtime/kernel_bridge"
require_relative "resilience/audit_logger"
require_relative "env_config"
require_relative "model_env"

module OllamaAgent
  class AgentAssembler
    MAX_TURNS = Agent::MAX_TURNS

    # Builds an Agent from keywords (convenience) or an explicit config.
    # Pass `client:` to inject a pre-built client (used by tests).
    def self.build(config: nil, client: nil, **kw)
      config ||= Agent::AgentConfig.new(**kw)
      new(config).assemble(client_override: client)
    end

    def initialize(config)
      @config = config
    end

    def assemble(client_override: nil)
      hooks = Streaming::Hooks.new
      logger = config.session.logger || build_default_logger
      client_manager = ClientManager.new(config: config, hooks: hooks)
      client = client_override || client_manager.build_default_client
      model_manager = ModelManager.new(client: client, default_model: config.model || default_model)
      prompt_builder = PromptBuilder.new(config: config)
      user_prompt_instance = config.user_prompt || UserPrompt.new(stdin: config.stdin, stdout: config.stdout)
      context_manager = Context::Manager.new(
        max_tokens: config.session.max_tokens,
        context_summarize: config.session.context_summarize
      )
      toolbox = Toolbox.new(config: config, logger: logger)
      session_manager = SessionManager.new(
        config: config,
        hooks: hooks,
        toolbox: toolbox,
        loop_detector: loop_detector,
        trace_logger: config.trace_logger,
        budget: budget,
        permissions: config.permissions,
        policies: config.policies,
        memory_manager: config.memory_manager
      )
      chat_coordinator = Agent::ChatCoordinator.new(
        client: client,
        model_manager: model_manager,
        config: config,
        hooks: hooks
      )
      kernel_bridge = Runtime::KernelBridge.new(
        session_manager: session_manager,
        toolbox: toolbox,
        hooks: hooks,
        loop_detector: loop_detector,
        memory_manager: config.memory_manager,
        config: config,
        logger: logger,
        permissions: config.permissions,
        policies: config.policies
      )

      agent = Agent.new(
        config: config,
        client: client,
        model_manager: model_manager,
        client_manager: client_manager,
        prompt_builder: prompt_builder,
        hooks: hooks,
        logger: logger,
        user_prompt: user_prompt_instance,
        context_manager: context_manager,
        toolbox: toolbox,
        session_manager: session_manager,
        chat_coordinator: chat_coordinator,
        kernel_bridge: kernel_bridge,
        budget: budget,
        loop_detector: loop_detector,
        trace_logger: config.trace_logger,
        memory_manager: config.memory_manager,
        policies: config.policies,
        permissions: config.permissions,
        approval_gate: config.approval_gate,
        max_turns: max_turns
      )
      attach_audit_logger(agent) if resolved_audit_enabled
      agent
    end

    private

    attr_reader :config

    def loop_detector
      @loop_detector ||= Core::LoopDetector.new
    end

    def budget
      @budget ||= config.budget || Core::Budget.new(
        max_steps: max_turns,
        max_tokens: config.session.max_tokens
      )
    end

    def max_turns
      @max_turns ||= EnvConfig.fetch_int(
        "OLLAMA_AGENT_MAX_TURNS",
        MAX_TURNS,
        strict: EnvConfig.strict_env?
      )
    end

    def default_model
      ModelEnv.default_chat_model
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

    def resolved_audit_enabled
      return false if config.runtime.audit == false
      return true if config.runtime.audit == true

      ENV.fetch("OLLAMA_AGENT_AUDIT", "0").strip == "1"
    end

    def attach_audit_logger(agent)
      adapter = Resilience::AuditLogger.new(hooks: agent.hooks)
      adapter.register!
    end
  end
end

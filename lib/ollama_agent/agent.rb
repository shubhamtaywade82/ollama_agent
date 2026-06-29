# frozen_string_literal: true

require "logger"
require "forwardable"

require_relative "agent_prompt"
require_relative "prompt_skills"
require_relative "console"
require_relative "ollama_connection"
require_relative "tools_schema"
require_relative "think_param"
require_relative "gemma_thought_content_parser"
require_relative "timeout_param"
require_relative "tool_content_parser"
require_relative "streaming/hooks"
require_relative "resilience/retry_middleware"
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
require_relative "agent/chat_coordinator"
require_relative "agent/turn_loop"
require_relative "core/budget"
require_relative "core/loop_detector"
require_relative "core/trace_logger"

module OllamaAgent
  # Runs a tool-calling loop against Ollama: read files, search, apply unified diffs.
  # Public entry: {#run}. Other instance methods are internal to the agent loop.
  class Agent
    MAX_TURNS = 64
    DEFAULT_HTTP_TIMEOUT = 120

    extend Forwardable

    attr_accessor :client
    attr_reader :config, :root, :hooks, :logger, :policies, :permissions

    # Backward-compatible new: when only config is given → Assembler.
    # When config + collaborators are given → normal constructor.
    # When no config given (old keyword style) → Assembler with those keywords.
    def self.new(config: nil, **kw)
      if config && kw.empty?
        AgentAssembler.build(config: config)
      elsif !config && kw.any?
        AgentAssembler.build(**kw)
      else
        super
      end
    end

    # Public convenience constructor — delegates to AgentAssembler.
    def self.build(**kw)
      AgentAssembler.build(**kw)
    end

    # Clean constructor — only accepts config + pre-built collaborators.
    def initialize(
      config:, client:, model_manager:,
      client_manager:, prompt_builder:,
      hooks:, logger:, user_prompt:,
      context_manager:, toolbox:,
      session_manager:, chat_coordinator:,
      kernel_bridge:, budget:, loop_detector:,
      trace_logger:, memory_manager:,
      policies:, permissions:,
      approval_gate:, max_turns:
    )
      @config = config
      @client = client
      @model_manager = model_manager
      @client_manager = client_manager
      @prompt_builder = prompt_builder
      @hooks = hooks
      @logger = logger
      @user_prompt = user_prompt
      @context_manager = context_manager
      @toolbox = toolbox
      @session_manager = session_manager
      @chat_coordinator = chat_coordinator
      @kernel_bridge = kernel_bridge
      @budget = budget
      @loop_detector = loop_detector
      @trace_logger = trace_logger
      @memory_manager = memory_manager
      @policies = policies
      @permissions = permissions
      @approval_gate = approval_gate
      @max_turns = max_turns
      @root = config.root || AgentRootResolver.resolve(config.root)
    end

    # Model access delegated to ModelManager
    def_delegators :@model_manager,
      :model, :assign_chat_model!, :model_accessible?,
      :list_local_model_names, :list_cloud_model_names

    # Tool access delegated to Toolbox (replaces SandboxedTools include)
    def_delegators :@toolbox,
      :read_file, :write_file, :edit_file, :apply_patch,
      :search, :index_ruby, :ruby_index, :read_directory, :repo_list, :grep_symbol,
      :list_files, :search_code, :search_with_ripgrep,
      :missing_tool_argument, :blank_tool_value?, :path_allowed?,
      :resolve_path, :disallowed_path_message, :coerce_tool_arguments,
      :tool_arg, :integer_or, :user_confirms_patch?

    # Prompt access delegated to PromptBuilder
    def_delegators :@prompt_builder, :system_prompt

    def_delegators :@chat_coordinator, :request_args

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

    private

    def execute_tool(name, args)
      context = {
        root: @root,
        read_only: @config.runtime.read_only,
        memory_manager: @memory_manager,
        shell_call_count: 0
      }
      @toolbox.execute(name, args, context: context)
    end

    def build_messages_for_run(query)
      @session_manager.build_messages_for_run(query)
    end
  end
end
# frozen_string_literal: true

require_relative "agent_prompt"
require_relative "prompt_skills"
require_relative "console"
require_relative "ollama_connection"
require_relative "tools_schema"
require_relative "sandboxed_tools"
require_relative "think_param"
require_relative "timeout_param"
require_relative "tool_content_parser"
require_relative "streaming/hooks"
require_relative "resilience/retry_middleware"
require_relative "resilience/audit_logger"
require_relative "context/manager"
require_relative "session/store"
require_relative "env_config"
require_relative "agent/agent_config"
require_relative "agent/client_wiring"
require_relative "agent/prompt_wiring"
require_relative "agent/session_wiring"

module OllamaAgent
  # Runs a tool-calling loop against Ollama: read files, search, apply unified diffs.
  # Public entry: {#run}. Other instance methods are internal to the agent loop.
  # rubocop:disable Metrics/ClassLength -- facade coordinates includes and turn loop
  class Agent
    include SandboxedTools
    include ClientWiring
    include PromptWiring
    include SessionWiring

    MAX_TURNS = 64
    DEFAULT_HTTP_TIMEOUT = 120

    attr_reader :client, :root, :hooks

    # @param config [AgentConfig, nil] when set, keyword options are ignored (use {Runner} or build {AgentConfig}).
    # rubocop:disable Metrics/ParameterLists
    # rubocop:disable Metrics/MethodLength
    def initialize(client: nil, config: nil, model: nil, root: nil, confirm_patches: true, http_timeout: nil,
                   think: nil,
                   read_only: false, patch_policy: nil,
                   skill_paths: nil, skills_enabled: nil, skills_include: nil, skills_exclude: nil,
                   external_skills_enabled: nil,
                   orchestrator: false, confirm_delegation: nil,
                   max_retries: nil, audit: nil,
                   session_id: nil, resume: false,
                   max_tokens: nil, context_summarize: nil,
                   stdin: $stdin, stdout: $stdout)
      cfg = config || AgentConfig.new(
        model: model, root: root, confirm_patches: confirm_patches, http_timeout: http_timeout, think: think,
        read_only: read_only, patch_policy: patch_policy,
        skill_paths: skill_paths, skills_enabled: skills_enabled, skills_include: skills_include,
        skills_exclude: skills_exclude, external_skills_enabled: external_skills_enabled,
        orchestrator: orchestrator, confirm_delegation: confirm_delegation,
        max_retries: max_retries, audit: audit, session_id: session_id, resume: resume,
        max_tokens: max_tokens, context_summarize: context_summarize, stdin: stdin, stdout: stdout
      )
      apply_agent_config(cfg)
      @user_prompt = UserPrompt.new(stdin: cfg.stdin, stdout: cfg.stdout)
      @context_manager = Context::Manager.new(max_tokens: @max_tokens, context_summarize: @context_summarize)
      @hooks = Streaming::Hooks.new
      attach_audit_logger if resolved_audit_enabled
      @client = client || build_default_client
    end
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/ParameterLists

    def run(query)
      messages = build_messages_for_run(query)
      execute_agent_turns(messages)
    end

    private

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- maps AgentConfig to ivars + resolved max turns
    def apply_agent_config(cfg)
      @model = cfg.model || default_model
      @root = File.expand_path(cfg.root || ENV.fetch("OLLAMA_AGENT_ROOT", Dir.pwd))
      @confirm_patches = cfg.confirm_patches
      @read_only = cfg.read_only
      @patch_policy = cfg.patch_policy
      @http_timeout_override = cfg.http_timeout
      @think = cfg.think
      @skill_paths = cfg.skill_paths
      @skills_enabled = cfg.skills_enabled
      @skills_include = cfg.skills_include
      @skills_exclude = cfg.skills_exclude
      @external_skills_enabled = cfg.external_skills_enabled
      @orchestrator = cfg.orchestrator
      @confirm_delegation = cfg.resolved_confirm_delegation
      @max_retries = cfg.max_retries
      @audit = cfg.audit
      @session_id = cfg.session_id
      @resume = cfg.resume
      @max_tokens = cfg.max_tokens
      @context_summarize = cfg.context_summarize
      strict = EnvConfig.strict_env?
      @max_turns = EnvConfig.fetch_int("OLLAMA_AGENT_MAX_TURNS", MAX_TURNS, strict: strict)
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    # rubocop:disable Metrics/MethodLength -- turn loop with early break
    def execute_agent_turns(messages)
      @current_turn = 0
      @max_turns.times do
        @current_turn += 1
        trimmed = trimmed_messages_for_chat(messages)
        message = chat_assistant_message(trimmed)
        tool_calls = tool_calls_from(message)
        persist_assistant_turn(messages, message)
        break if tool_calls.empty?

        append_tool_results(messages, tool_calls)
      end
      emit_turn_complete(messages)
      warn_max_turns_if_needed
    end
    # rubocop:enable Metrics/MethodLength

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

      warn "ollama_agent: maximum tool rounds (#{@max_turns}) reached"
    end

    def current_turn
      @current_turn || 0
    end

    def tool_calls_from(message)
      calls = message.tool_calls || []
      return calls unless calls.empty? && ToolContentParser.enabled?

      ToolContentParser.synthetic_calls(message.content)
    end

    def chat_assistant_message(messages)
      if @hooks.subscribed?(:on_token)
        stream_assistant_message(messages)
      else
        block_assistant_message(messages)
      end
    end

    def block_assistant_message(messages)
      response = @client.chat(**chat_request_args(messages))
      message = response.message
      raise Error, "Empty assistant message" if message.nil?

      announce_assistant_content(message)
      message
    end

    def stream_assistant_message(messages)
      ollama_hooks = {
        on_token: ->(token) { @hooks.emit(:on_token, { token: token, turn: current_turn }) }
      }
      response = @client.chat(**chat_request_args(messages), hooks: ollama_hooks)
      message = response.message
      raise Error, "Empty assistant message" if message.nil?

      message
    end

    def chat_request_args(messages)
      base_chat_request_args(messages).tap do |args|
        th = resolve_think
        args[:think] = th unless th.nil?
      end
    end

    def base_chat_request_args(messages)
      {
        messages: messages,
        tools: OllamaAgent.tools_for(read_only: @read_only, orchestrator: @orchestrator),
        model: @model,
        options: { temperature: 0.2 }
      }
    end

    def announce_assistant_content(message)
      Console.puts_assistant_message(message)
    end

    def resolve_think
      ThinkParam.resolve(@think)
    end

    def default_model
      ENV["OLLAMA_AGENT_MODEL"] || Ollama::Config.new.model
    end
  end
  # rubocop:enable Metrics/ClassLength
end

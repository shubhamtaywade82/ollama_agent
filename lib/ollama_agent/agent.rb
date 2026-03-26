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

module OllamaAgent
  # Runs a tool-calling loop against Ollama: read files, search, apply unified diffs.
  # rubocop:disable Metrics/ClassLength -- Facade for chat loop, tools, and HTTP client wiring
  class Agent
    include SandboxedTools

    MAX_TURNS = 64
    # ollama-client defaults to 30s; multi-turn tool chats often need longer on local hardware.
    DEFAULT_HTTP_TIMEOUT = 120

    attr_reader :client, :root, :hooks

    # rubocop:disable Metrics/ParameterLists -- CLI and tests pass explicit dependencies
    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def initialize(client: nil, model: nil, root: nil, confirm_patches: true, http_timeout: nil, think: nil,
                   read_only: false, patch_policy: nil,
                   skill_paths: nil, skills_enabled: nil, skills_include: nil, skills_exclude: nil,
                   external_skills_enabled: nil,
                   orchestrator: false, confirm_delegation: nil,
                   max_retries: nil, audit: nil,
                   session_id: nil, resume: false)
      @model = model || default_model
      @root = File.expand_path(root || ENV.fetch("OLLAMA_AGENT_ROOT", Dir.pwd))
      @confirm_patches = confirm_patches
      @read_only = read_only
      @patch_policy = patch_policy
      @http_timeout_override = http_timeout
      @think = think
      @skill_paths = skill_paths
      @skills_enabled = skills_enabled
      @skills_include = skills_include
      @skills_exclude = skills_exclude
      @external_skills_enabled = external_skills_enabled
      @orchestrator = orchestrator
      @confirm_delegation = confirm_delegation.nil? || confirm_delegation
      @max_retries      = max_retries
      @audit            = audit
      @session_id       = session_id
      @resume           = resume
      @context_manager  = Context::Manager.new
      @hooks = Streaming::Hooks.new
      attach_audit_logger if resolved_audit_enabled
      @client = client || build_default_client
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
    # rubocop:enable Metrics/ParameterLists

    def run(query)
      prior    = @session_id && @resume ? Session::Store.resume(session_id: @session_id, root: @root) : []
      messages = prior.empty? ? [{ role: "system", content: system_prompt }] : prior
      messages << { role: "user", content: query }
      Session::Store.save(session_id: @session_id, root: @root, message: messages.last) if @session_id

      execute_agent_turns(messages)
    end

    private

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- turn counter + hooks + context trim + session save
    def execute_agent_turns(messages)
      @current_turn = 0
      max_turns.times do
        @current_turn += 1
        trimmed    = @context_manager.trim(messages)
        message    = chat_assistant_message(trimmed)
        tool_calls = tool_calls_from(message)
        messages << message.to_h
        save_message_to_session(message.to_h)
        break if tool_calls.empty?

        append_tool_results(messages, tool_calls)
      end

      @hooks.emit(:on_complete, { messages: messages, turns: @current_turn })
      return unless ENV["OLLAMA_AGENT_DEBUG"] == "1" && @current_turn >= max_turns

      warn "ollama_agent: maximum tool rounds (#{max_turns}) reached"
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    def current_turn
      @current_turn || 0
    end

    def tool_calls_from(message)
      calls = message.tool_calls || []
      return calls unless calls.empty? && ToolContentParser.enabled?

      ToolContentParser.synthetic_calls(message.content)
    end

    def max_turns
      Integer(ENV.fetch("OLLAMA_AGENT_MAX_TURNS", MAX_TURNS.to_s))
    rescue ArgumentError, TypeError
      MAX_TURNS
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
      args = {
        messages: messages,
        tools: OllamaAgent.tools_for(read_only: @read_only, orchestrator: @orchestrator),
        model: @model,
        options: { temperature: 0.2 }
      }
      th = resolve_think
      args[:think] = th unless th.nil?
      args
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

    # rubocop:disable Metrics/MethodLength -- wraps Ollama client with retry; needs 11 lines
    def build_default_client
      config = Ollama::Config.new
      @http_timeout_seconds = resolved_http_timeout_seconds
      config.timeout = @http_timeout_seconds
      OllamaConnection.apply_env_to_config(config)
      ollama_client = Ollama::Client.new(config: config)
      Resilience::RetryMiddleware.new(
        client: ollama_client,
        max_attempts: resolved_max_retries,
        hooks: @hooks,
        base_delay: resolved_retry_base_delay
      )
    end
    # rubocop:enable Metrics/MethodLength

    def resolved_max_retries
      return @max_retries unless @max_retries.nil?

      v = ENV.fetch("OLLAMA_AGENT_MAX_RETRIES", nil)
      return Resilience::RetryMiddleware::DEFAULT_MAX_ATTEMPTS if v.nil? || v.to_s.strip.empty?

      Integer(v)
    rescue ArgumentError, TypeError
      Resilience::RetryMiddleware::DEFAULT_MAX_ATTEMPTS
    end

    def resolved_retry_base_delay
      v = ENV.fetch("OLLAMA_AGENT_RETRY_BASE_DELAY", nil)
      return Resilience::RetryMiddleware::DEFAULT_BASE_DELAY if v.nil? || v.to_s.strip.empty?

      Float(v)
    rescue ArgumentError, TypeError
      Resilience::RetryMiddleware::DEFAULT_BASE_DELAY
    end

    def resolved_audit_enabled
      return @audit unless @audit.nil?

      ENV.fetch("OLLAMA_AGENT_AUDIT", "0") == "1"
    end

    def audit_log_dir
      custom = ENV.fetch("OLLAMA_AGENT_AUDIT_LOG_PATH", nil)
      return custom if custom && !custom.to_s.strip.empty?

      File.join(@root, ".ollama_agent", "logs")
    end

    def attach_audit_logger
      Resilience::AuditLogger.new(log_dir: audit_log_dir, hooks: @hooks).attach
    end

    def resolved_http_timeout_seconds
      parsed = TimeoutParam.parse_positive(@http_timeout_override)
      return parsed if parsed

      parsed = TimeoutParam.parse_positive(ENV.fetch("OLLAMA_AGENT_TIMEOUT", nil))
      return parsed if parsed

      DEFAULT_HTTP_TIMEOUT
    end

    # rubocop:disable Metrics/MethodLength -- compose + optional orchestrator addon
    def system_prompt
      base = @read_only ? AgentPrompt.self_review_text : AgentPrompt.text
      composed = PromptSkills.compose(
        base: base,
        skills_enabled: resolved_skills_enabled,
        skills_include: resolved_skills_include,
        skills_exclude: resolved_skills_exclude,
        skill_paths: resolved_skill_paths,
        external_skills_enabled: resolved_external_skills_enabled
      )
      return composed unless @orchestrator

      [composed, AgentPrompt.orchestrator_addon].join("\n\n---\n\n")
    end
    # rubocop:enable Metrics/MethodLength

    def resolved_skills_enabled
      return @skills_enabled unless @skills_enabled.nil?

      PromptSkills.env_truthy("OLLAMA_AGENT_SKILLS", default: true)
    end

    def resolved_skills_include
      return @skills_include unless @skills_include.nil?

      PromptSkills.parse_id_list(ENV.fetch("OLLAMA_AGENT_SKILLS_INCLUDE", nil))
    end

    def resolved_skills_exclude
      return @skills_exclude unless @skills_exclude.nil?

      PromptSkills.parse_id_list(ENV.fetch("OLLAMA_AGENT_SKILLS_EXCLUDE", nil))
    end

    def resolved_skill_paths
      @skill_paths
    end

    def resolved_external_skills_enabled
      return @external_skills_enabled unless @external_skills_enabled.nil?

      PromptSkills.env_truthy("OLLAMA_AGENT_EXTERNAL_SKILLS", default: true)
    end

    def append_tool_results(messages, tool_calls)
      tool_calls.each do |tool_call|
        @hooks.emit(:on_tool_call, { name: tool_call.name, args: tool_call.arguments || {}, turn: current_turn })
        result = execute_tool(tool_call.name, tool_call.arguments || {})
        @hooks.emit(:on_tool_result, { name: tool_call.name, result: result.to_s, turn: current_turn })
        messages << tool_message(tool_call, result)
        save_message_to_session(messages.last)
      end
    end

    def save_message_to_session(msg)
      return unless @session_id

      Session::Store.save(session_id: @session_id, root: @root, message: msg)
    end

    def tool_message(tool_call, result)
      msg = {
        role: "tool",
        name: tool_call.name,
        content: result.to_s
      }
      id = tool_call.id
      msg[:tool_call_id] = id if id && !id.to_s.empty?
      msg
    end
  end
  # rubocop:enable Metrics/ClassLength
end

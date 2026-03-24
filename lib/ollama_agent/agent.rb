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

module OllamaAgent
  # Runs a tool-calling loop against Ollama: read files, search, apply unified diffs.
  # rubocop:disable Metrics/ClassLength -- Facade for chat loop, tools, and HTTP client wiring
  class Agent
    include SandboxedTools

    MAX_TURNS = 64
    # ollama-client defaults to 30s; multi-turn tool chats often need longer on local hardware.
    DEFAULT_HTTP_TIMEOUT = 120

    attr_reader :client, :root

    # rubocop:disable Metrics/ParameterLists -- CLI and tests pass explicit dependencies
    # rubocop:disable Metrics/MethodLength
    def initialize(client: nil, model: nil, root: nil, confirm_patches: true, http_timeout: nil, think: nil,
                   read_only: false, patch_policy: nil,
                   skill_paths: nil, skills_enabled: nil, skills_include: nil, skills_exclude: nil,
                   external_skills_enabled: nil)
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
      @client = client || build_default_client
    end
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/ParameterLists

    def run(query)
      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: query }
      ]

      execute_agent_turns(messages)
    end

    private

    def execute_agent_turns(messages)
      max_turns.times do
        message = chat_assistant_message(messages)
        tool_calls = tool_calls_from(message)

        messages << message.to_h
        return if tool_calls.empty?

        append_tool_results(messages, tool_calls)
      end

      warn "ollama_agent: maximum tool rounds (#{max_turns}) reached" if ENV["OLLAMA_AGENT_DEBUG"] == "1"
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
      response = @client.chat(**chat_request_args(messages))

      message = response.message
      raise Error, "Empty assistant message" if message.nil?

      announce_assistant_content(message)
      message
    end

    def chat_request_args(messages)
      args = {
        messages: messages,
        tools: @read_only ? READ_ONLY_TOOLS : TOOLS,
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

    def build_default_client
      config = Ollama::Config.new
      @http_timeout_seconds = resolved_http_timeout_seconds
      config.timeout = @http_timeout_seconds
      OllamaConnection.apply_env_to_config(config)
      Ollama::Client.new(config: config)
    end

    def resolved_http_timeout_seconds
      parsed = TimeoutParam.parse_positive(@http_timeout_override)
      return parsed if parsed

      parsed = TimeoutParam.parse_positive(ENV.fetch("OLLAMA_AGENT_TIMEOUT", nil))
      return parsed if parsed

      DEFAULT_HTTP_TIMEOUT
    end

    def system_prompt
      base = @read_only ? AgentPrompt.self_review_text : AgentPrompt.text
      PromptSkills.compose(
        base: base,
        skills_enabled: resolved_skills_enabled,
        skills_include: resolved_skills_include,
        skills_exclude: resolved_skills_exclude,
        skill_paths: resolved_skill_paths,
        external_skills_enabled: resolved_external_skills_enabled
      )
    end

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
        result = execute_tool(tool_call.name, tool_call.arguments || {})
        messages << tool_message(tool_call, result)
      end
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

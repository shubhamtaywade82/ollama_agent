# frozen_string_literal: true

require_relative "agent_prompt"
require_relative "tools_schema"
require_relative "sandboxed_tools"
require_relative "tool_content_parser"

module OllamaAgent
  # Runs a tool-calling loop against Ollama: read files, search, apply unified diffs.
  class Agent
    include SandboxedTools

    MAX_TURNS = 64
    # ollama-client defaults to 30s; multi-turn tool chats often need longer on local hardware.
    DEFAULT_HTTP_TIMEOUT = 120

    attr_reader :client, :root

    def initialize(client: nil, model: nil, root: nil, confirm_patches: true, http_timeout: nil)
      @model = model || default_model
      @root = File.expand_path(root || ENV.fetch("OLLAMA_AGENT_ROOT", Dir.pwd))
      @confirm_patches = confirm_patches
      @http_timeout_override = http_timeout
      @client = client || build_default_client
    end

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
      response = @client.chat(
        messages: messages,
        tools: TOOLS,
        model: @model,
        options: { temperature: 0.2 }
      )

      message = response.message
      raise Error, "Empty assistant message" if message.nil?

      announce_assistant_content(message)
      message
    end

    def announce_assistant_content(message)
      content = message.content
      puts content if content && !content.to_s.empty?
    end

    def default_model
      ENV["OLLAMA_AGENT_MODEL"] || Ollama::Config.new.model
    end

    def build_default_client
      config = Ollama::Config.new
      @http_timeout_seconds = resolved_http_timeout_seconds
      config.timeout = @http_timeout_seconds
      Ollama::Client.new(config: config)
    end

    def resolved_http_timeout_seconds
      parsed = parse_positive_timeout(@http_timeout_override)
      return parsed if parsed

      parsed = parse_positive_timeout(ENV.fetch("OLLAMA_AGENT_TIMEOUT", nil))
      return parsed if parsed

      DEFAULT_HTTP_TIMEOUT
    end

    def system_prompt
      AgentPrompt.text
    end

    def parse_positive_timeout(raw)
      return nil if raw.nil?
      return nil if raw.is_a?(String) && raw.strip.empty?

      t = Integer(raw)
      return nil unless t.positive?

      t
    rescue ArgumentError, TypeError
      nil
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
end

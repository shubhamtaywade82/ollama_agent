# frozen_string_literal: true

require_relative "tools_schema"
require_relative "sandboxed_tools"

module OllamaAgent
  # Runs a tool-calling loop against Ollama: read files, search, apply unified diffs.
  class Agent
    include SandboxedTools

    MAX_TURNS = 32

    attr_reader :client, :root

    def initialize(client: nil, model: nil, root: nil, confirm_patches: true)
      @model = model || default_model
      @root = File.expand_path(root || ENV.fetch("OLLAMA_AGENT_ROOT", Dir.pwd))
      @confirm_patches = confirm_patches
      @client = client || Ollama::Client.new
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
      MAX_TURNS.times do
        message = chat_assistant_message(messages)
        tool_calls = message.tool_calls || []
        messages << message.to_h
        return if tool_calls.empty?

        append_tool_results(messages, tool_calls)
      end

      raise Error, "Maximum agent turns (#{MAX_TURNS}) exceeded"
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

    def system_prompt
      <<~PROMPT
        You are a coding assistant. You can read files, search code, and apply small patches using unified diffs.
        Only access paths under the project root. Explain your plan before using tools.
        When editing, produce a unified diff suitable for `patch -p1` from the project root.
        Example:
        --- a/lib/example.rb
        +++ b/lib/example.rb
        @@ -1,3 +1,3 @@
        -old
        +new
      PROMPT
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

# frozen_string_literal: true

require_relative "tools_schema"
require_relative "sandboxed_tools"

module OllamaAgent
  # Runs a tool-calling loop against Ollama: read files, search, apply unified diffs.
  class Agent
    include SandboxedTools

    MAX_TURNS = 64

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
      max_turns.times do
        message = chat_assistant_message(messages)
        tool_calls = message.tool_calls || []
        messages << message.to_h
        return if tool_calls.empty?

        append_tool_results(messages, tool_calls)
      end

      warn "ollama_agent: maximum tool rounds (#{max_turns}) reached" if ENV["OLLAMA_AGENT_DEBUG"] == "1"
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

    def system_prompt
      <<~PROMPT
        You are a coding assistant with tools: list_files, read_file, search_code, edit_file.
        Work only under the project root. Briefly state your plan, then use tools.

        For README or documentation updates that should reflect the codebase:
        1) list_files on "." or "lib" (and read ollama_agent.gemspec if present) to see structure.
        2) read_file the targets you will mention (e.g. README.md, lib/ollama_agent.rb).
        3) edit_file last, using a unified diff produced like `git diff`: --- a/<path>, +++ b/<path>, @@ ... @@,
           then lines with leading space (unchanged context), `-` (remove), `+` (add). Copy exact existing lines from
           read_file for `-`/context; @@ line counts must match the hunk.

        Never invent file contents—only edit what you have read. Never put @@ before the +++ line for the same file.
        When the task is done, reply with a brief summary and stop calling tools.
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

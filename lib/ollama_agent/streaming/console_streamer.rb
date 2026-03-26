# frozen_string_literal: true

require_relative "../console"

module OllamaAgent
  module Streaming
    # Attaches to a Hooks instance to print live streaming output to stdout.
    # Auto-attached by CLI when --stream is passed and stdout is a TTY.
    class ConsoleStreamer
      def attach(hooks)
        hooks.on(:on_token)       { |p| print p[:token]; $stdout.flush }
        hooks.on(:on_tool_call)   { |p| warn Console.tool_call_line(p[:name], p[:args]) }
        hooks.on(:on_tool_result) { |p| warn Console.tool_result_line(p[:name], p[:result]) }
        hooks.on(:on_complete)    { puts }
      end
    end
  end
end

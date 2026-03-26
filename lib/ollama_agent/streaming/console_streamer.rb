# frozen_string_literal: true

require_relative "../console"

module OllamaAgent
  module Streaming
    # Attaches to a Hooks instance to print live streaming output to stdout.
    # Auto-attached by CLI when --stream is passed and stdout is a TTY.
    class ConsoleStreamer
      def attach(hooks)
        hooks.on(:on_token) do |payload|
          print payload[:token]
          $stdout.flush
        end
        hooks.on(:on_tool_call)   { |payload| warn Console.tool_call_line(payload[:name], payload[:args]) }
        hooks.on(:on_tool_result) { |payload| warn Console.tool_result_line(payload[:name], payload[:result]) }
        hooks.on(:on_complete)    { puts }
      end
    end
  end
end

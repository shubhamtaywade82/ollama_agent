# frozen_string_literal: true

require_relative "../console"

module OllamaAgent
  module Streaming
    # Attaches to a Hooks instance to print live streaming output to stdout.
    # Auto-attached by CLI when --stream is passed and stdout is a TTY.
    class ConsoleStreamer
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one subscriber block per hook
      def attach(hooks)
        hooks.on(:on_thinking) do |payload|
          Console.write_streaming_thinking_fragment(payload[:token])
        end
        hooks.on(:on_token) do |payload|
          Console.finalize_streaming_thinking_before_content!
          Console.write_stream_token(payload[:token])
        end
        hooks.on(:on_tool_call)   { |payload| warn Console.tool_call_line(payload[:name], payload[:args]) }
        hooks.on(:on_tool_result) { |payload| warn Console.tool_result_line(payload[:name], payload[:result]) }
        hooks.on(:on_complete) do
          Console.close_streaming_thinking_if_still_open!
          puts
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    end
  end
end

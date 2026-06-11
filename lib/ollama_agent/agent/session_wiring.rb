# frozen_string_literal: true

module OllamaAgent
  class Agent
    module SessionWiring
      def build_messages_for_run(query)
        @session_manager.build_messages_for_run(query)
      end

      def dispatch_tool_results(messages, tool_calls)
        @session_manager.dispatch_tool_results(messages, tool_calls)
      end

      private

      def save_message_to_session(msg)
        @session_manager.save_message_to_session(msg)
      end

      def tool_message(tool_call, result)
        @session_manager.tool_message(tool_call, result)
      end
    end
  end
end
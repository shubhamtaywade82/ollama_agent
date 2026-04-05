# frozen_string_literal: true

module OllamaAgent
  class Agent
    # Session resume/save and tool message formatting for the chat transcript.
    module SessionWiring
      private

      # rubocop:disable Metrics/CyclomaticComplexity
      def build_messages_for_run(query)
        prior    = @session_id && @resume ? Session::Store.resume(session_id: @session_id, root: @root) : []
        messages = prior.empty? ? [{ role: "system", content: system_prompt }] : prior
        first = messages.first
        unless first && (first[:role] == "system" || first["role"] == "system")
          messages.unshift({ role: "system", content: system_prompt })
        end

        messages << { role: "user", content: query }
        Session::Store.save(session_id: @session_id, root: @root, message: messages.last) if @session_id

        messages
      end
      # rubocop:enable Metrics/CyclomaticComplexity

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
  end
end

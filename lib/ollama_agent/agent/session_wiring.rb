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
          name = tool_call.name
          args = tool_call.arguments || {}

          @hooks.emit(:on_tool_call, { name: name, args: args, turn: current_turn })
          @loop_detector&.record!(name, args)

          result = platform_guarded_tool_call(name, args)

          @hooks.emit(:on_tool_result, { name: name, result: result.to_s, turn: current_turn })
          @memory_manager&.record_tool_call(name, args, result)
          messages << tool_message(tool_call, result)
          save_message_to_session(messages.last)
        end
      end

      # Run permission / policy guards before delegating to execute_tool.
      def platform_guarded_tool_call(name, args)
        ctx = build_tool_context

        # Permission check
        if @permissions && !@permissions.allowed?(name)
          return "Permission denied: tool '#{name}' is not allowed under the current permission profile (#{@permissions.profile})."
        end

        # Policy check
        if @policies
          rejection = @policies.evaluate(name, args, ctx)
          return rejection if rejection
        end

        execute_tool(name, args)
      end

      def build_tool_context
        {
          root: @root,
          read_only: @read_only,
          memory_manager: @memory_manager,
          shell_call_count: @shell_call_count || 0
        }
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

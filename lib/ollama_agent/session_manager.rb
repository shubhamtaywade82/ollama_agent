# frozen_string_literal: true

module OllamaAgent
  class SessionManager
    attr_reader :config, :hooks, :toolbox, :loop_detector, :trace_logger, :budget, :permissions, :policies, :memory_manager

    def initialize(config:, hooks:, toolbox:, loop_detector:, trace_logger:, budget:, permissions:, policies:, memory_manager:)
      @config = config
      @hooks = hooks
      @toolbox = toolbox
      @loop_detector = loop_detector
      @trace_logger = trace_logger
      @budget = budget
      @permissions = permissions
      @policies = policies
      @memory_manager = memory_manager
    end

    def build_messages_for_run(query)
      session_config = @config.session
      prior = session_config.session_id && session_config.resume ? Session::Store.resume(session_id: session_config.session_id, root: @config.root) : []
      messages = prior.empty? ? [{ role: "system", content: system_prompt }] : prior
      first = messages.first
      messages.unshift({ role: "system", content: system_prompt }) unless first && (first[:role] == "system" || first["role"] == "system")

      messages << { role: "user", content: query }
      Session::Store.save(session_id: session_config.session_id, root: @config.root, message: messages.last) if session_config.session_id

      messages
    end

    def dispatch_tool_results(messages, tool_calls)
      append_tool_results(messages, tool_calls)
    end

    def save_message_to_session(msg)
      session_id = @config.session.session_id
      return unless session_id

      Session::Store.save(session_id: session_id, root: @config.root, message: msg)
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

    private

    def system_prompt
      @config.runtime.system_prompt || (@config.runtime.read_only ? AgentPrompt.self_review_text : AgentPrompt.text)
    end

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

    def platform_guarded_tool_call(name, args)
      ctx = build_tool_context

      return "Permission denied: tool '#{name}' is not allowed under the current permission profile (#{@permissions.profile})." if @permissions && !@permissions.allowed?(name)

      if @policies
        rejection = @policies.evaluate(name, args, ctx)
        return rejection if rejection
      end

      @toolbox.execute(name, args, context: ctx)
    end

    def build_tool_context
      {
        root: @config.root,
        read_only: @config.runtime.read_only,
        memory_manager: @memory_manager,
        shell_call_count: 0
      }
    end

    def current_turn
      # SessionManager doesn't track turns directly; this is passed from TurnLoop
      # For now, return 0 as a fallback (TurnLoop will pass the actual turn number)
      0
    end
  end
end
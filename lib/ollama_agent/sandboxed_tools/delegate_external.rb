# frozen_string_literal: true

module OllamaAgent
  module SandboxedTools
    # Orchestrator tools: list and delegate to external CLI agents.
    module DelegateExternal
      private

      def execute_list_external_agents(_args)
        return "list_external_agents is only available in orchestrator mode." unless @orchestrator

        require "json"
        rows = external_registry.agents.map { |a| ExternalAgents::Probe.fetch_status(a) }
        JSON.pretty_generate(rows)
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def execute_delegate_to_agent_tool(args)
        return "delegate_to_agent is only available in orchestrator mode." unless @orchestrator
        return "delegate_to_agent is disabled in read-only mode." if @read_only

        id = tool_arg(args, "agent_id")
        task = tool_arg(args, "task")
        return missing_tool_argument("delegate_to_agent", "agent_id") if blank_tool_value?(id)
        return missing_tool_argument("delegate_to_agent", "task") if blank_tool_value?(task)

        agent_def = external_registry.find(id.to_s)
        return "Unknown agent_id: #{id}. Call list_external_agents first." unless agent_def

        exe = ExternalAgents::Probe.resolve_executable(agent_def)
        return "Agent #{id} is not available (not on PATH). Check list_external_agents." unless exe

        return "Cancelled by user" if @confirm_delegation && !user_confirms_delegate?(id, task)

        timeout_sec = integer_or(tool_arg(args, "timeout_seconds"), agent_def["timeout_sec"] || 600)
        paths = tool_arg(args, "paths")
        paths = [] unless paths.is_a?(Array)

        ExternalAgents::Runner.run(
          agent_def: agent_def,
          root: @root,
          executable: exe,
          task: task,
          context_summary: tool_arg(args, "context_summary").to_s,
          paths: paths,
          timeout_sec: timeout_sec
        )
      rescue ArgumentError => e
        e.message
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def external_registry
        @external_registry ||= ExternalAgents::Registry.load
      end

      def user_confirms_delegate?(agent_id, task)
        user_prompt.confirm_delegate(agent_id, task)
      end
    end
  end
end

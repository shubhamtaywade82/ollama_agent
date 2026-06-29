# frozen_string_literal: true

require_relative "base"
require_relative "enhanced_registry"

module OllamaAgent
  module Tools
    class MemorySearch < Base
      tool_name        "memory_search"
      tool_description "Search stored memory entries by pattern match across keys and values."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      query: { type: "string", description: "Search query (substring match on keys and values)" },
                      namespace: { type: "string", description: "Namespace to search (default: 'default')" },
                      top_k: { type: "integer", description: "Max results (default: 10)" }
                    },
                    required: ["query"]
                  })

      def call(args, context: {})
        memory = context[:memory_manager]
        return "memory_search: no memory manager in context" unless memory

        query     = args["query"].to_s
        namespace = args["namespace"] || "default"
        top_k     = [args["top_k"]&.to_i || 10, 50].min

        entries = memory.search(query, namespace: namespace)
        return "No memories found matching #{query.inspect}" if entries.empty?

        entries.first(top_k).map do |k, v|
          "#{k}: #{v.to_s[0, 120]}"
        end.join("\n")
      end
    end

    class SessionSummary < Base
      tool_name        "session_summary"
      tool_description "Summarize recent tool calls and observations from short-term memory."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      n: { type: "integer", description: "Number of recent entries to summarize (default: 15)" }
                    },
                    required: []
                  })

      def call(args, context: {})
        memory = context[:memory_manager]
        return "session_summary: no memory manager in context" unless memory

        n = [args["n"]&.to_i || 15, 50].min
        recent = memory.recent_context(n)

        return "No recent activity to summarize" if recent.empty?

        lines = recent.map.with_index do |entry, i|
          prefix = if entry[:type] == :tool_call
                     "[CALL]"
                   else
                     entry[:type] == :tool_result ? "[RESULT]" : "[OBS]"
                   end
          text = entry[:content].is_a?(Hash) ? entry[:content].inspect : entry[:content].to_s
          "#{i + 1}. #{prefix} #{text[0, 200]}"
        end

        {
          entries: lines.size,
          summary: lines.join("\n")
        }
      end
    end

    EnhancedRegistry.register(MemorySearch)
    EnhancedRegistry.register(SessionSummary)
  end
end

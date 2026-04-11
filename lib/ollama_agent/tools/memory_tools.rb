# frozen_string_literal: true

require_relative "base"

module OllamaAgent
  module Tools
    # Store a fact in long-term memory for future sessions.
    class MemoryStore < Base
      tool_name        "memory_store"
      tool_description "Store a key-value fact in persistent long-term memory for use in future sessions"
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
        type: "object",
        properties: {
          key:       { type: "string", description: "Unique key for this fact", minLength: 1 },
          value:     { type: "string", description: "Value to store" },
          namespace: { type: "string", description: "Namespace (default: 'default')" }
        },
        required: ["key", "value"]
      })

      def call(args, context: {})
        memory = context[:memory_manager]
        return "memory_store: no memory manager in context" unless memory

        key       = args["key"].to_s.strip
        value     = args["value"].to_s
        namespace = args["namespace"] || "default"

        memory.remember(key, value, tier: :long_term, namespace: namespace)
        "Stored: #{key} = #{value.inspect[0, 80]}"
      end
    end

    # Recall a fact from long-term memory.
    class MemoryRecall < Base
      tool_name        "memory_recall"
      tool_description "Recall a stored fact from long-term memory by key"
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
        type: "object",
        properties: {
          key:       { type: "string", description: "Key to look up", minLength: 1 },
          namespace: { type: "string", description: "Namespace (default: 'default')" }
        },
        required: ["key"]
      })

      def call(args, context: {})
        memory = context[:memory_manager]
        return "memory_recall: no memory manager in context" unless memory

        key       = args["key"].to_s.strip
        namespace = args["namespace"] || "default"
        value     = memory.recall(key, namespace: namespace)

        value.nil? ? "No memory found for key: #{key}" : value.to_s
      end
    end

    # List stored memory keys
    class MemoryList < Base
      tool_name        "memory_list"
      tool_description "List all keys stored in long-term memory"
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
        type: "object",
        properties: {
          namespace: { type: "string", description: "Namespace to list (default: 'default')" }
        },
        required: []
      })

      def call(args, context: {})
        memory = context[:memory_manager]
        return "memory_list: no memory manager in context" unless memory

        namespace = args["namespace"] || "default"
        entries   = memory.list(namespace: namespace)

        return "No memories stored in namespace: #{namespace}" if entries.empty?

        entries.map { |k, v| "#{k}: #{v.to_s[0, 60]}" }.join("\n")
      end
    end

    # Delete a stored memory key
    class MemoryDelete < Base
      tool_name        "memory_delete"
      tool_description "Delete a key from long-term memory"
      tool_risk        :medium
      tool_requires_approval false
      tool_schema({
        type: "object",
        properties: {
          key:       { type: "string", description: "Key to delete", minLength: 1 },
          namespace: { type: "string", description: "Namespace (default: 'default')" }
        },
        required: ["key"]
      })

      def call(args, context: {})
        memory = context[:memory_manager]
        return "memory_delete: no memory manager in context" unless memory

        key       = args["key"].to_s.strip
        namespace = args["namespace"] || "default"
        memory.forget(key, namespace: namespace)
        "Deleted memory key: #{key}"
      end
    end
  end
end

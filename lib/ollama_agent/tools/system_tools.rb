# frozen_string_literal: true

require "json"
require_relative "base"
require_relative "enhanced_registry"

module OllamaAgent
  module Tools
    class AuditLog < Base
      tool_name        "audit_log"
      tool_description "Append a structured entry to the agent audit log (.agent_audit.jsonl)."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      action: { type: "string", description: "Action name (e.g. 'write_file', 'delete_file')" },
                      details: { type: "object", description: "Structured details about the action" }
                    },
                    required: ["action"]
                  })

      def call(args, context: {})
        root = context[:root] || Dir.pwd

        branch = begin
          `git -C #{Shellwords.shellescape(root)} rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
        rescue StandardError
          "unknown"
        end

        entry = {
          ts: Time.now.iso8601,
          action: args["action"],
          details: args["details"] || {},
          branch: branch
        }

        log_path = File.join(root, ".agent_audit.jsonl")
        File.open(log_path, "a") { |f| f.puts(entry.to_json) }
        "Logged: #{args["action"]}"
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end

    class AskHuman < Base
      tool_name        "ask_human"
      tool_description "Pause execution and ask the human operator a yes/no or open-ended question."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      question: { type: "string", description: "Question to ask the human" },
                      type: {
                        type: "string",
                        enum: %w[yes_no open],
                        description: "Type of answer expected"
                      }
                    },
                    required: ["question"]
                  })

      def call(args, _context = {})
        question = args["question"].to_s
        qtype    = args["type"] || "yes_no"

        $stdout.puts "\n[AGENT ASKS] #{question}"
        $stdout.print qtype == "yes_no" ? "[y/n] " : "> "
        answer = $stdin.gets.to_s.chomp

        return { answer: answer, approved: answer.match?(/\A\s*y(?:es)?\s*\z/i) } if qtype == "yes_no"

        { answer: answer }
      end
    end

    class SetContext < Base
      tool_name        "set_context"
      tool_description "Set a runtime context variable shared across tool calls within a session."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      key: { type: "string", description: "Context key" },
                      value: { type: "string", description: "Context value" }
                    },
                    required: %w[key value]
                  })

      def call(args, context: {})
        context_manager = context[:context_manager]
        return "set_context: no context manager available" unless context_manager

        key   = args["key"].to_s.strip
        value = args["value"].to_s
        context_manager.set(key, value)
        "Context set: #{key} = #{value}"
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end

    EnhancedRegistry.register(AuditLog)
    EnhancedRegistry.register(AskHuman)
    EnhancedRegistry.register(SetContext)
  end
end

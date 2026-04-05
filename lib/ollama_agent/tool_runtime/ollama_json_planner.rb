# frozen_string_literal: true

require "json"
require "ollama_client"

module OllamaAgent
  module ToolRuntime
    # Asks an Ollama chat model for the next tool call as a single JSON object.
    class OllamaJsonPlanner
      # @param model [String, nil] when nil or blank, uses {OllamaAgent::Agent} rules:
      #   `ENV["OLLAMA_AGENT_MODEL"]` if set, else `Ollama::Config.new.model`
      def initialize(client:, model: nil, chat_options: nil)
        @client = client
        @model = resolve_model(model)
        @chat_options = chat_options || { temperature: 0.2 }
      end

      def next_step(context:, memory:, registry:)
        prompt = build_prompt(context: context, memory: memory, registry: registry)
        response = @client.chat(
          model: @model,
          messages: [{ role: "user", content: prompt }],
          options: @chat_options
        )
        content = assistant_content(response)
        JsonExtractor.extract_object(content)
      end

      private

      def resolve_model(explicit)
        s = explicit.to_s.strip
        return s unless s.empty?

        env = ENV["OLLAMA_AGENT_MODEL"].to_s.strip
        return env unless env.empty?

        Ollama::Config.new.model
      end

      def build_prompt(context:, memory:, registry:)
        ctx = context.is_a?(String) ? context : JSON.generate(context)
        tools_block = merged_tool_descriptions(memory, registry)
        <<~PROMPT.strip
          You are an agent step planner. Reply with exactly one JSON object and no other text.
          Keys: "tool" (string, required) and "args" (object, optional, default {}).
          Use only tool names listed under Available tools.

          Available tools:
          #{tools_block}

          Context:
          #{ctx}

          Prior steps (JSON):
          #{memory_json(memory)}
        PROMPT
      end

      def merged_tool_descriptions(memory, registry)
        base = registry.descriptions_for_prompt
        extra = memory.tool_descriptions_for_prompt
        extra.empty? ? base : "#{extra}\n#{base}"
      end

      def memory_json(memory)
        JSON.generate(memory.recent.map { |step| memory_step_row(step) })
      end

      def memory_step_row(step)
        row = { "thought" => step[:thought], "result" => step[:result] }
        attach_action_to_row(row, step[:action])
        row
      end

      def attach_action_to_row(row, action)
        return unless action.is_a?(Hash)

        tool = action[:tool]
        row["tool"] = tool.respond_to?(:name) ? tool.name : nil
        row["args"] = action[:args]
      end

      def assistant_content(response)
        msg = response.message
        return "" if msg.nil?

        if msg.respond_to?(:content)
          c = msg.content
          return c.to_s unless c.nil?
        end
        return msg["content"].to_s if msg.is_a?(Hash)

        msg.to_s
      end
    end
  end
end

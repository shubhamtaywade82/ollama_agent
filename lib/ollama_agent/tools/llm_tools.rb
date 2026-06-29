# frozen_string_literal: true

require "json"
require "net/http"
require_relative "base"
require_relative "enhanced_registry"

module OllamaAgent
  module Tools
    class LlmComplete < Base
      tool_name        "llm_complete"
      tool_description "Send a prompt to an LLM and return the completion. Useful for sub-task delegation."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      prompt: { type: "string", description: "Prompt text to send" },
                      model: { type: "string", description: "Model name (default: from agent config)" },
                      schema: {
                        type: "object",
                        description: "Optional JSON schema to enforce structured output"
                      }
                    },
                    required: ["prompt"]
                  })

      def call(args, context: {})
        prompt = args["prompt"].to_s
        model  = args["model"] || context[:model] || ENV["OLLAMA_AGENT_MODEL"] || "qwen2.5-coder:7b"
        schema = args["schema"]

        body = {
          model: model,
          prompt: prompt,
          stream: false,
          options: { temperature: 0.3 }
        }

        if schema
          body[:format] = schema
        end

        host = ENV.fetch("OLLAMA_HOST", "http://localhost:11434")
        uri  = URI("#{host}/api/generate")

        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)

        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                     read_timeout: 120, open_timeout: 10) { |h| h.request(req) }

        return "HTTP #{resp.code}: #{resp.message}" unless resp.is_a?(Net::HTTPSuccess)

        data = JSON.parse(resp.body)
        { response: data["response"], model: model, done: data["done"] }
      rescue StandardError => e
        { error: e.message }
      end
    end

    class LlmReview < Base
      tool_name        "llm_review"
      tool_description "Ask an LLM to review a code snippet and return structured feedback."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      code: { type: "string", description: "Code to review" },
                      instructions: { type: "string", description: "Review instructions / focus areas" }
                    },
                    required: %w[code instructions]
                  })

      REVIEW_PROMPT = <<~PROMPT
        Review the following code. Return structured feedback as JSON with keys:
        - issues: array of strings describing problems
        - suggestions: array of improvement suggestions
        - verdict: "approve" or "request_changes"

        Instructions: %s

        Code:
        ```%s
        %s
        ```
      PROMPT

      def call(args, context: {})
        code         = args["code"].to_s
        instructions = args["instructions"].to_s

        ext   = detect_language(code)
        prompt = REVIEW_PROMPT % [instructions, ext, code]

        model = context[:model] || ENV["OLLAMA_AGENT_MODEL"] || "qwen2.5-coder:7b"
        host  = ENV.fetch("OLLAMA_HOST", "http://localhost:11434")

        uri  = URI("#{host}/api/generate")
        req  = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req.body = JSON.generate({
          model: model,
          prompt: prompt,
          stream: false,
          options: { temperature: 0.2 },
          format: {
            type: "object",
            properties: {
              issues: { type: "array", items: { type: "string" } },
              suggestions: { type: "array", items: { type: "string" } },
              verdict: { type: "string", enum: ["approve", "request_changes"] }
            },
            required: %w[issues suggestions verdict]
          }
        })

        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                     read_timeout: 120, open_timeout: 10) { |h| h.request(req) }

        return "HTTP #{resp.code}" unless resp.is_a?(Net::HTTPSuccess)

        data = JSON.parse(resp.body)
        JSON.parse(data["response"])
      rescue StandardError => e
        { error: e.message, issues: [], suggestions: [], verdict: "error" }
      end

      private

      def detect_language(code)
        if code.match?(/^\s*(def |class |module |require|Rails\.|ActiveRecord)/)
          "ruby"
        elsif code.match?(/^\s*(import |export |function |const |interface |type )/)
          "typescript"
        elsif code.match?(/^\s*(import |def |class |from )/)
          "python"
        else
          ""
        end
      end
    end

    class EmbedText < Base
      tool_name        "embed_text"
      tool_description "Generate an embedding vector for text using Ollama embeddings API."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      text: { type: "string", description: "Text to embed" },
                      model: { type: "string", description: "Embedding model (default: nomic-embed-text)" }
                    },
                    required: ["text"]
                  })

      def call(args, _context = {})
        text  = args["text"].to_s
        model = args["model"] || "nomic-embed-text"

        host = ENV.fetch("OLLAMA_HOST", "http://localhost:11434")
        uri  = URI("#{host}/api/embeddings")

        req  = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req.body = JSON.generate({ model: model, prompt: text })

        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                     read_timeout: 30, open_timeout: 10) { |h| h.request(req) }

        return "HTTP #{resp.code}" unless resp.is_a?(Net::HTTPSuccess)

        data = JSON.parse(resp.body)
        vector = data["embedding"]
        {
          vector: vector.first(10), # first 10 dims as preview
          dimensions: vector.size,
          model: model
        }
      rescue StandardError => e
        { error: e.message }
      end
    end

    EnhancedRegistry.register(LlmComplete)
    EnhancedRegistry.register(LlmReview)
    EnhancedRegistry.register(EmbedText)
  end
end

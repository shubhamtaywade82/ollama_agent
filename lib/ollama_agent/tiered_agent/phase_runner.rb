# frozen_string_literal: true

require "json"

module OllamaAgent
  module TieredAgent
    # Executes each of the four model phases in the tiered swap loop.
    #
    # Each public method targets a specific model tier and returns a parsed Hash.
    # The caller is responsible for loading/unloading VRAM state — this class only
    # assembles the prompt payload and delegates to the Ollama client.
    class PhaseRunner
      # JSON schema enforced by the Ollama structured-output API for planning responses.
      PLANNING_SCHEMA = {
        "type" => "object",
        "required" => %w[rationale tool_call tool_instructions],
        "properties" => {
          "rationale" => { "type" => "string" },
          "tool_call" => {
            "type" => "string",
            "enum" => %w[execute_bash read_source_file write_output_file exit_success]
          },
          "tool_instructions" => { "type" => "string" }
        }
      }.freeze

      # JSON schema enforced for verification responses.
      VERIFICATION_SCHEMA = {
        "type" => "object",
        "required" => %w[confirmed_success reasons],
        "properties" => {
          "confirmed_success" => { "type" => "boolean" },
          "reasons" => { "type" => "string" }
        }
      }.freeze

      # @param client       [#chat]  Ollama client (RetryMiddleware or Ollama::Client)
      # @param vram_options [Hash]   built by {VramOptions.build}; injected as `options:`
      # @param models       [Hash]   override tier → model name; keys :small, :medium, :large
      def initialize(client:, vram_options:, models: {})
        @client       = client
        @vram_options = vram_options
        @models       = {
          small: models.fetch(:small, ModelTier::SMALL),
          medium: models.fetch(:medium, ModelTier::MEDIUM),
          large: models.fetch(:large, ModelTier::LARGE)
        }
      end

      # Phase 1 — planning via Medium model.
      #
      # @param goal      [String]
      # @param state_log [StateLog]
      # @return [Hash] {"rationale"=>, "tool_call"=>, "tool_instructions"=>}
      def run_planning(goal:, state_log:)
        messages = [
          { "role" => "system",
            "content" => "You are the system architect planner. " \
                         "Select the next tool to achieve the objective based on current state logs. " \
                         "When the goal is fully achieved, set tool_call to exit_success." },
          { "role" => "user",
            "content" => "Objective: #{goal}\nCurrent System State: #{state_log.to_json}" }
        ]

        parse_json_response chat(model: :medium, messages: messages, format: PLANNING_SCHEMA)
      end

      # Phase 2 — argument extraction via Small model.
      #
      # @param tool_name    [String]
      # @param instructions [String]
      # @return [Hash] tool-specific argument map
      def run_extraction(tool_name:, instructions:)
        schema = extraction_schema_for(tool_name)
        messages = [
          { "role" => "system",
            "content" => "Extract strict JSON parameters for the tool: #{tool_name}. " \
                         "Return only the required fields, no extra keys." },
          { "role" => "user",
            "content" => "Instructions: #{instructions}" }
        ]

        parse_json_response chat(model: :small, messages: messages, format: schema)
      end

      # Phase 4 — verification via Medium model.
      #
      # @param tool   [String]
      # @param args   [Hash]
      # @param output [String]
      # @return [Hash] {"confirmed_success"=> Boolean, "reasons"=> String}
      def run_verification(tool:, args:, output:)
        truncated = output.to_s[0, 2048]
        messages = [
          { "role" => "system",
            "content" => "Analyse the tool execution log and determine whether the operation succeeded." },
          { "role" => "user",
            "content" => "Tool: #{tool}\nArguments: #{JSON.generate(args)}\nOutput:\n#{truncated}" }
        ]

        parse_json_response chat(model: :medium, messages: messages, format: VERIFICATION_SCHEMA)
      end

      # Phase 5 — escalation via Large model (free-form text; no schema).
      #
      # @param goal      [String]
      # @param state_log [StateLog]
      # @return [String] supervisor recommendation
      def run_escalation(goal:, state_log:)
        messages = [
          { "role" => "system",
            "content" => "You are an advanced supervisor engine. " \
                         "The autonomous execution loop is deadlocked. " \
                         "Diagnose the root cause and provide a concrete revised plan." },
          { "role" => "user",
            "content" => "Goal: #{goal}\nExecution History: #{state_log.to_json}" }
        ]

        raw = chat(model: :large, messages: messages)
        raw.message.content.to_s
      end

      private

      def chat(model:, messages:, format: nil)
        args = { messages: messages, model: @models[model], options: @vram_options }
        args[:format] = format if format
        @client.chat(**args)
      end

      def parse_json_response(raw)
        content = raw.message.content.to_s
        raise OllamaAgent::Error, "Empty response from model" if content.strip.empty?

        JSON.parse(content)
      rescue JSON::ParserError => e
        raise OllamaAgent::Error, "Model returned invalid JSON: #{e.message} (got: #{content[0, 120].inspect})"
      end

      def extraction_schema_for(tool_name)
        case tool_name
        when "execute_bash"
          {
            "type" => "object",
            "required" => ["command"],
            "properties" => { "command" => { "type" => "string" } }
          }
        else
          {
            "type" => "object",
            "required" => %w[path data],
            "properties" => {
              "path" => { "type" => "string" },
              "data" => { "type" => "string" }
            }
          }
        end
      end
    end
  end
end

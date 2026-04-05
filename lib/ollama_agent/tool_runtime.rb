# frozen_string_literal: true

# Generic think → act → observe loop for JSON-shaped tool plans (plugin tools).
# Distinct from {OllamaAgent::Agent}, which uses Ollama native /api/chat tool_calls for coding.
module OllamaAgent
  module ToolRuntime
    class Error < OllamaAgent::Error; end

    class JsonParseError < Error; end

    class InvalidPlanError < Error; end

    class MaxStepsExceeded < Error; end
  end
end

require_relative "tool_runtime/tool"
require_relative "tool_runtime/memory"
require_relative "tool_runtime/registry"
require_relative "tool_runtime/executor"
require_relative "tool_runtime/json_extractor"
require_relative "tool_runtime/ollama_json_planner"
require_relative "tool_runtime/loop"

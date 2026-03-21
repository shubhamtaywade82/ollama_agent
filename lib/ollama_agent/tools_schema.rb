# frozen_string_literal: true

module OllamaAgent
  # JSON tool definitions passed to Ollama /api/chat.
  TOOLS = [
    {
      type: "function",
      function: {
        name: "read_file",
        description: "Read the content of a file under the project root.",
        parameters: {
          type: "object",
          properties: { path: { type: "string" } },
          required: ["path"]
        }
      }
    },
    {
      type: "function",
      function: {
        name: "search_code",
        description: "Search for a pattern in files (case-sensitive). Returns matching lines with file names.",
        parameters: {
          type: "object",
          properties: {
            pattern: { type: "string" },
            directory: { type: "string" }
          },
          required: ["pattern"]
        }
      }
    },
    {
      type: "function",
      function: {
        name: "edit_file",
        description: "Apply a unified diff. Use standard git diff format; apply with patch -p1 from project root.",
        parameters: {
          type: "object",
          properties: {
            path: { type: "string" },
            diff: { type: "string" }
          },
          required: %w[path diff]
        }
      }
    }
  ].freeze
end

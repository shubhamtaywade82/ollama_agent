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
        name: "list_files",
        description: "List file paths under a directory relative to project root (skips .git). " \
                     "Use first to see layout (lib/, exe/, gemspec) before updating README or docs.",
        parameters: {
          type: "object",
          properties: {
            directory: { type: "string", description: "Directory to scan (default: .)" },
            max_entries: { type: "integer", description: "Max paths to return (default 100, max 500)" }
          },
          required: []
        }
      }
    },
    {
      type: "function",
      function: {
        name: "edit_file",
        description: "Apply a unified diff to the file given by path. " \
                     "Use git unified format: --- a/<path>, then +++ b/<path>, then @@ hunk, then lines with " \
                     "leading space, `-`, or `+`. Copy exact lines from read_file; @@ counts must match the hunk. " \
                     "Paths in ---/+++ must match path. patch -p1 from project root.",
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

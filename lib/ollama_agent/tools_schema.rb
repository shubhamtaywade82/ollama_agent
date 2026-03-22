# frozen_string_literal: true

module OllamaAgent
  # JSON tool definitions passed to Ollama /api/chat.
  TOOLS = [
    {
      type: "function",
      function: {
        name: "read_file",
        description: "Read the content of a file under the project root. " \
                     "Optional start_line and end_line (1-based, inclusive) return only that slice.",
        parameters: {
          type: "object",
          properties: {
            path: { type: "string" },
            start_line: { type: "integer", description: "First line to include (1-based)" },
            end_line: { type: "integer", description: "Last line to include (1-based); omit through EOF" }
          },
          required: ["path"]
        }
      }
    },
    {
      type: "function",
      function: {
        name: "search_code",
        description: "Search: mode text = ripgrep/grep (default). " \
                     "Modes class, module, constant, method = Prism Ruby index (no grep).",
        parameters: {
          type: "object",
          properties: {
            pattern: { type: "string" },
            directory: { type: "string" },
            mode: {
              type: "string",
              description: "text (default), class, module, constant, or method (Prism Ruby index)"
            }
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

  READ_ONLY_TOOLS = TOOLS.reject { |t| t.dig(:function, :name) == "edit_file" }.freeze
end

# frozen_string_literal: true

# Tool JSON schemas for Ollama /api/chat (base + optional orchestrator tools).
module OllamaAgent # rubocop:disable Metrics/ModuleLength -- schema tables; splitting would scatter definitions
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

  ORCHESTRATOR_LIST_TOOL = {
    type: "function",
    function: {
      name: "list_external_agents",
      description: "List configured external CLI agents (Claude, Gemini, Codex, Cursor, etc.): availability, " \
                   "path, version, capabilities. Call before delegate_to_agent to choose an agent_id.",
      parameters: {
        type: "object",
        properties: {},
        required: []
      }
    }
  }.freeze

  ORCHESTRATOR_DELEGATE_TOOL = {
    type: "function",
    function: {
      name: "delegate_to_agent",
      description: "Run a task via an external CLI agent (non-interactive argv only). Use after " \
                   "list_external_agents; pass a concise task and context_summary; prefer exploring the repo " \
                   "with read_file/search_code first to save tokens.",
      parameters: {
        type: "object",
        properties: {
          agent_id: { type: "string", description: "Registry id (e.g. claude_cli, gemini_cli)" },
          task: { type: "string", description: "What the external agent should do" },
          context_summary: { type: "string", description: "Short context from your own exploration" },
          paths: {
            type: "array",
            items: { type: "string" },
            description: "Optional relative paths under project root to mention in the handoff"
          },
          timeout_seconds: {
            type: "integer",
            description: "Optional timeout (defaults from registry or 600)"
          }
        },
        required: %w[agent_id task]
      }
    }
  }.freeze

  ORCHESTRATOR_TOOLS = [ORCHESTRATOR_LIST_TOOL, ORCHESTRATOR_DELEGATE_TOOL].freeze
  ORCHESTRATOR_READ_ONLY_TOOLS = [ORCHESTRATOR_LIST_TOOL].freeze
  ORCHESTRATOR_TOOLS_SCHEMA_VERSION = "1"

  def self.tools_for(read_only:, orchestrator:)
    base = read_only ? READ_ONLY_TOOLS : TOOLS
    return base unless orchestrator

    base + (read_only ? ORCHESTRATOR_READ_ONLY_TOOLS : ORCHESTRATOR_TOOLS)
  end
end

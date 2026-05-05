# frozen_string_literal: true

module OllamaAgent
  module Tools
    # Built-in Ollama /api/chat tool schemas (read/write + optional orchestrator tools).
    # Extend via {.register}; query with {.tools_for}.
    # rubocop:disable Metrics/ModuleLength -- schema tables; single registry for OCP
    module BuiltInSchemas
      class << self
        # Register an extra built-in schema (OCP: add tools without editing core tables).
        def register(schema, read_only: false, read_write_too: false)
          raise ArgumentError, "schema must be a Hash" unless schema.is_a?(Hash)

          extras << { schema: schema, read_only: read_only, read_write_too: read_write_too }
        end

        def reset_registrations!
          @extras = []
        end

        def extras
          @extras ||= []
        end

        def tools_for(read_only:, orchestrator:, custom_schemas:)
          base = base_tools(read_only: read_only) + custom_schemas + extra_schemas_for(read_only: read_only)
          return base unless orchestrator

          base + orchestrator_addon(read_only: read_only)
        end

        def base_tools(read_only:)
          read_only ? READ_ONLY_TOOLS : CORE_TOOLS
        end

        def orchestrator_addon(read_only:)
          read_only ? ORCHESTRATOR_READ_ONLY_TOOLS : ORCHESTRATOR_TOOLS
        end

        def extra_schemas_for(read_only:)
          extras.filter_map do |entry|
            next entry[:schema] if entry[:read_write_too]
            next entry[:schema] unless read_only
            next entry[:schema] if entry[:read_only]

            nil
          end
        end
      end

      # Core tool definitions (single source of truth for built-ins).
      CORE_TOOLS = [
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
                max_entries: { type: "integer", description: "Max paths to return (default 100, max 500)" },
                max_depth: {
                  type: "integer",
                  description: "Optional max path depth under directory (omit = unlimited; 1 = immediate children only)"
                }
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
                         "leading space, `-`, or `+`. Copy exact lines from read_file; @@ counts must match the " \
                         "hunk. Paths in ---/+++ must match path. patch -p1 from project root.",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string" },
                diff: { type: "string" }
              },
              required: %w[path diff]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "write_file",
            description: "Create or overwrite a file under the project root with full UTF-8 content. " \
                         "Use for new files or complete rewrites. Prefer edit_file for surgical changes.",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "File path relative to project root" },
                content: { type: "string", description: "Full file content to write" }
              },
              required: %w[path content]
            }
          }
        }
      ].freeze

      READ_ONLY_TOOLS = CORE_TOOLS.reject { |t| %w[edit_file write_file].include?(t.dig(:function, :name)) }.freeze

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
    end
    # rubocop:enable Metrics/ModuleLength
  end
end

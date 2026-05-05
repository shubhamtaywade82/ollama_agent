# frozen_string_literal: true

require_relative "tools/built_in_schemas"

# Re-exports built-in tool schemas and the composed +tools_for+ helper for Ollama /api/chat.
module OllamaAgent
  TOOLS = Tools::BuiltInSchemas::CORE_TOOLS
  READ_ONLY_TOOLS = Tools::BuiltInSchemas::READ_ONLY_TOOLS
  ORCHESTRATOR_LIST_TOOL = Tools::BuiltInSchemas::ORCHESTRATOR_LIST_TOOL
  ORCHESTRATOR_DELEGATE_TOOL = Tools::BuiltInSchemas::ORCHESTRATOR_DELEGATE_TOOL
  ORCHESTRATOR_TOOLS = Tools::BuiltInSchemas::ORCHESTRATOR_TOOLS
  ORCHESTRATOR_READ_ONLY_TOOLS = Tools::BuiltInSchemas::ORCHESTRATOR_READ_ONLY_TOOLS
  ORCHESTRATOR_TOOLS_SCHEMA_VERSION = Tools::BuiltInSchemas::ORCHESTRATOR_TOOLS_SCHEMA_VERSION

  def self.tools_for(read_only:, orchestrator:)
    Tools::BuiltInSchemas.tools_for(
      read_only: read_only,
      orchestrator: orchestrator,
      custom_schemas: Tools::Registry.custom_schemas
    )
  end
end

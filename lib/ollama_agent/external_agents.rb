# frozen_string_literal: true

# External agent delegation historically shelled out to local CLIs (Open3). That path was removed in
# E13: {OllamaAgent::ExternalAgents::Runner} now calls {OllamaAgent::LLM::AnthropicClient} over HTTPS
# using +ANTHROPIC_API_KEY+. Registry entries use +transport: anthropic_api+ (see default_agents.yml).

require_relative "external_agents/env_helpers"
require_relative "external_agents/path_validator"
require_relative "external_agents/delegate_logger"
require_relative "external_agents/argv_interp"
require_relative "external_agents/registry"
require_relative "external_agents/probe"
require_relative "external_agents/runner"

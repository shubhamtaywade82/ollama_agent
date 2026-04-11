# frozen_string_literal: true

require_relative "agent"
require_relative "streaming/hooks"
require_relative "streaming/console_streamer"

module OllamaAgent
  # Stable public facade for library consumers.
  # Configure via Runner.build, then call #run.
  #
  # @example
  #   runner = OllamaAgent::Runner.build(root: "/my/project", stream: true, audit: true)
  #   runner.hooks.on(:on_token) { |p| print p[:token] }
  #   runner.run("Refactor the auth module")
  class Runner
    # @return [Streaming::Hooks] the hooks bus — attach subscribers before calling #run
    def hooks
      @agent.hooks
    end

    # @return [String, nil] the current session id
    attr_reader :session_id

    # Build a configured Runner.
    #
    # @param root [String] project root directory (default: Dir.pwd)
    # @param model [String, nil] Ollama model name
    # @param stream [Boolean] enable streaming token output to stdout
    # @param session_id [String, nil] named session for persistence
    # @param resume [Boolean] load prior session messages before running
    # @param max_retries [Integer] HTTP retry attempts (0 = disable)
    # @param audit [Boolean] enable structured audit logging
    # @param read_only [Boolean] disable write tools
    # @param skills_enabled [Boolean] include bundled prompt skills
    # @param skill_paths [Array<String>, nil] extra .md skill paths
    # @param confirm_patches [Boolean] prompt before applying patches
    # @param orchestrator [Boolean] enable external agent delegation
    # @param think [String, nil] thinking mode (true/false/high/medium/low)
    # @param http_timeout [Integer, nil] HTTP timeout in seconds
    # @param stdin [IO] input for patch/write/delegate confirmations (default +$stdin+)
    # @param stdout [IO] output for confirmation prompts (default +$stdout+)
    # @param provider [String, nil] provider name: "ollama" | "openai" | "anthropic" | "auto" (v2)
    # @param permissions [Runtime::Permissions, nil] tool permission profile (v2)
    # @param budget [Core::Budget, nil] token/step budget (v2)
    # @param memory [Memory::Manager, nil] memory manager instance (v2)
    # @param trace [Boolean] enable trace logging to stdout (v2)
    # @return [Runner]
    # rubocop:disable Metrics/ParameterLists -- library facade must expose all Agent options
    def self.build(
      root:            Dir.pwd,
      model:           nil,
      stream:          false,
      session_id:      nil,
      resume:          false,
      max_tokens:      nil,
      context_summarize: false,
      max_retries:     nil,
      audit:           nil,
      read_only:       false,
      skills_enabled:  true,
      skill_paths:     nil,
      confirm_patches: true,
      orchestrator:    false,
      think:           nil,
      http_timeout:    nil,
      stdin:           $stdin,
      stdout:          $stdout,
      # v2 platform options
      provider:        nil,
      permissions:     nil,
      budget:          nil,
      memory:          nil,
      trace:           false
    )
      new(
        root: root, model: model, stream: stream,
        session_id: session_id, resume: resume,
        max_tokens: max_tokens, context_summarize: context_summarize,
        max_retries: max_retries, audit: audit, read_only: read_only,
        skills_enabled: skills_enabled, skill_paths: skill_paths,
        confirm_patches: confirm_patches, orchestrator: orchestrator,
        think: think, http_timeout: http_timeout,
        stdin: stdin, stdout: stdout,
        provider: provider, permissions: permissions,
        budget: budget, memory: memory, trace: trace
      )
    end
    # rubocop:enable Metrics/ParameterLists

    # Execute a query. Blocks until the agent loop completes.
    # @param query [String]
    def run(query)
      agent.run(query)
    end

    protected

    # Exposed for spec stubbing only.
    attr_reader :agent

    private

    # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
    def initialize(root:, model:, stream:, session_id:, resume:,
                   max_tokens:, context_summarize:,
                   max_retries:, audit:, read_only:, skills_enabled:, skill_paths:,
                   confirm_patches:, orchestrator:, think:, http_timeout:,
                   stdin:, stdout:,
                   provider: nil, permissions: nil, budget: nil, memory: nil, trace: false)
      @session_id = session_id

      trace_logger = trace ? Core::TraceLogger.new(format: :human) : nil

      config = Agent::AgentConfig.new(
        root: root,
        model: model,
        confirm_patches: confirm_patches,
        http_timeout: http_timeout,
        think: think,
        read_only: read_only,
        skills_enabled: skills_enabled,
        skill_paths: skill_paths ? Array(skill_paths) : nil,
        orchestrator: orchestrator,
        session_id: session_id,
        resume: resume,
        max_retries: max_retries,
        audit: audit,
        max_tokens: max_tokens,
        context_summarize: context_summarize,
        stdin: stdin,
        stdout: stdout,
        provider_name:  provider,
        permissions:    permissions,
        budget:         budget,
        memory_manager: memory,
        trace_logger:   trace_logger
      )
      @agent = Agent.new(config: config)

      Streaming::ConsoleStreamer.new.attach(@agent.hooks) if stream
    end
    # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists
  end
end

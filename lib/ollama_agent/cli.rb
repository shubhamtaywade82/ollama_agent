# frozen_string_literal: true

require "thor"

require_relative "agent"
require_relative "external_agents"
require_relative "prompt_skills"
require_relative "runtime/permissions"
require_relative "plugins/registry"
require_relative "plugins/loader"

module OllamaAgent
  # Thor CLI for single-shot and interactive agent sessions.
  # rubocop:disable Metrics/ClassLength -- Thor commands and shared helpers
  class CLI < Thor
    default_task :ask

    def self.exit_on_failure?
      true
    end

    desc "ask [QUERY]", "Run a task, or interactive TUI when QUERY is omitted (default when no subcommand)"
    method_option :model, type: :string, desc: "Ollama model (default: OLLAMA_AGENT_MODEL or ollama-client default)"
    method_option :interactive, type: :boolean, aliases: "-i",
                                desc: "-i without --tui: line REPL; empty QUERY defaults to TUI"
    method_option :tui, type: :boolean, default: false,
                        desc: "TTY UI; on by default for empty QUERY unless line REPL (-i without --tui)"
    method_option :tui_god, type: :boolean, default: false,
                            desc: "With --tui: auto-select first option in interactive lists (dangerous)"
    method_option :read_only, type: :boolean, default: false, aliases: "-R",
                              desc: "Read/search only (no edit_file, write_file, patches, or delegation)"
    method_option :yes, type: :boolean, aliases: "-y", desc: "Apply patches without confirmation"
    method_option :root, type: :string, desc: "Project root (default: OLLAMA_AGENT_ROOT or cwd)"
    method_option :timeout, type: :numeric, aliases: "-t", desc: "HTTP timeout seconds (default 120)"
    method_option :think, type: :string, desc: "Thinking mode: true|false|high|medium|low (see OLLAMA_AGENT_THINK)"
    method_option :no_skills, type: :boolean, default: false,
                              desc: "Disable bundled prompt skills (same as OLLAMA_AGENT_SKILLS=0)"
    method_option :skill_paths, type: :string,
                                desc: "Extra .md paths or dirs, colon-separated; merged with OLLAMA_AGENT_SKILL_PATHS"
    method_option :stream, type: :boolean, default: false,
                           desc: "Stream tokens to terminal as they arrive (OLLAMA_AGENT_STREAM=1)"
    method_option :audit, type: :boolean, default: false,
                          desc: "Enable structured audit log under .ollama_agent/logs/ (OLLAMA_AGENT_AUDIT=1)"
    method_option :max_retries, type: :numeric,
                                desc: "HTTP retry attempts (0=disable, default 3)"
    method_option :session, type: :string,  desc: "Named session id (saves/resumes conversation)"
    method_option :resume,  type: :boolean, default: false,
                            desc: "Resume the named (or most recent) session"
    method_option :max_tokens, type: :numeric,
                               desc: "Context window budget (OLLAMA_AGENT_MAX_TOKENS)"
    method_option :context_summarize, type: :boolean, default: false,
                                      desc: "Summarize dropped context vs sliding window"
    method_option :provider, type: :string,
                             desc: "Model provider: ollama (default) | openai | anthropic | auto"
    method_option :permissions, type: :string,
                                desc: "Permission profile: read_only | standard (default) | developer | full"
    method_option :trace, type: :boolean, default: false,
                          desc: "Enable structured trace logging (OLLAMA_AGENT_TRACE=1)"
    def ask(query = nil)
      load_plugins!
      apply_session_interactive_tui_flags!(query)
      validate_tui_options!
      run_ask!(query)
    end

    desc "orchestrate [QUERY]", "Like ask, plus delegate to external CLI agents (Claude, Gemini, …)"
    method_option :model, type: :string, desc: "Ollama model (default: OLLAMA_AGENT_MODEL or ollama-client default)"
    method_option :interactive, type: :boolean, aliases: "-i",
                                desc: "-i without --tui: line REPL; empty QUERY defaults to TUI"
    method_option :tui, type: :boolean, default: false,
                        desc: "TTY UI; on by default for empty QUERY unless line REPL (-i without --tui)"
    method_option :tui_god, type: :boolean, default: false,
                            desc: "With --tui: auto-select first option in interactive lists (dangerous)"
    method_option :read_only, type: :boolean, default: false, aliases: "-R",
                              desc: "Read/search only (no edit_file, write_file, patches, or delegation)"
    method_option :yes, type: :boolean, aliases: "-y", desc: "Apply patches and run delegations without confirmation"
    method_option :root, type: :string, desc: "Project root (default: OLLAMA_AGENT_ROOT or cwd)"
    method_option :timeout, type: :numeric, aliases: "-t", desc: "HTTP timeout seconds (default 120)"
    method_option :think, type: :string, desc: "Thinking mode: true|false|high|medium|low (see OLLAMA_AGENT_THINK)"
    method_option :no_skills, type: :boolean, default: false,
                              desc: "Disable bundled prompt skills (same as OLLAMA_AGENT_SKILLS=0)"
    method_option :skill_paths, type: :string,
                                desc: "Extra .md paths or dirs, colon-separated; merged with OLLAMA_AGENT_SKILL_PATHS"
    method_option :stream, type: :boolean, default: false,
                           desc: "Stream tokens to terminal as they arrive (OLLAMA_AGENT_STREAM=1)"
    method_option :audit, type: :boolean, default: false,
                          desc: "Enable structured audit log under .ollama_agent/logs/ (OLLAMA_AGENT_AUDIT=1)"
    method_option :max_retries, type: :numeric,
                                desc: "HTTP retry attempts (0=disable, default 3)"
    method_option :max_tokens, type: :numeric,
                               desc: "Context window budget (OLLAMA_AGENT_MAX_TOKENS)"
    method_option :context_summarize, type: :boolean, default: false,
                                      desc: "Summarize dropped context vs sliding window"
    def orchestrate(query = nil)
      load_plugins!
      apply_session_interactive_tui_flags!(query)
      validate_tui_options!
      run_orchestrate!(query)
    end

    desc "sessions", "List saved sessions for the current project root"
    method_option :root, type: :string, desc: "Project root (default: OLLAMA_AGENT_ROOT or cwd)"
    def sessions
      root = resolved_root_for_self_review
      list = Session::Store.list(root: root)
      if list.empty?
        puts "No sessions found in #{root}"
        return
      end
      puts "SESSION ID                      STARTED"
      list.each { |s| puts format("%-30<id>s  %<started>s", id: s.session_id, started: s.started_at) }
    end

    desc "agents", "List configured external CLI agents and whether they are on PATH"
    def agents
      reg = ExternalAgents::Registry.load
      ExternalAgents::Probe.print_table(reg)
    end

    desc "doctor", "Alias for agents"
    def doctor
      agents
    end

    desc "self_review", "Self-review / improvement: --mode analysis | interactive | automated (see help)"
    method_option :mode, type: :string, default: "analysis",
                         desc: "analysis (1)=read-only report; interactive (2)=confirm patches in tree; " \
                               "automated (3)=sandbox+RSpec+optional --apply"
    long_desc <<~HELP
      Modes:
        analysis     Read-only tools; prints a report; no writes (default).
        interactive  Full tools on --root; you confirm each patch (like `ask`); optional -y / --semi.
        automated    Temp sandbox, agent edits, `bundle exec rspec`; optional --apply to merge back.

      Aliases: 1/2/3, readonly, fix, confirm, sandbox, full.
    HELP
    method_option :model, type: :string, desc: "Ollama model (default: OLLAMA_AGENT_MODEL or ollama-client default)"
    method_option :root, type: :string, desc: "Project root (default: OLLAMA_AGENT_ROOT or cwd)"
    method_option :timeout, type: :numeric, aliases: "-t", desc: "HTTP timeout seconds (default 120)"
    method_option :think, type: :string, desc: "Thinking mode: true|false|high|medium|low (see OLLAMA_AGENT_THINK)"
    method_option :yes, type: :boolean, aliases: "-y",
                        desc: "interactive/automated: apply patches without confirmation"
    method_option :semi, type: :boolean, default: true,
                         desc: "interactive/automated: auto-approve obvious patches; prompt for risky (default: true)"
    method_option :apply, type: :boolean, default: false,
                          desc: "automated only: after green tests, copy changed files from sandbox into --root"
    method_option :no_skills, type: :boolean, default: false,
                              desc: "Disable bundled prompt skills (same as OLLAMA_AGENT_SKILLS=0)"
    method_option :skill_paths, type: :string,
                                desc: "Extra .md paths or dirs, colon-separated; merged with OLLAMA_AGENT_SKILL_PATHS"
    method_option :stream, type: :boolean, default: false,
                           desc: "Stream tokens to terminal as they arrive (OLLAMA_AGENT_STREAM=1)"
    method_option :max_tokens, type: :numeric,
                               desc: "Context window budget (OLLAMA_AGENT_MAX_TOKENS)"
    method_option :context_summarize, type: :boolean, default: false,
                                      desc: "Summarize dropped context vs sliding window"
    method_option :verify, type: :string,
                           desc: "automated only: comma-separated checks after agent (default: rspec or " \
                                 "OLLAMA_AGENT_IMPROVE_VERIFY). Steps: syntax, rubocop, rspec"
    method_option :no_ruby_mastery, type: :boolean, default: false,
                                    desc: "Skip prepending ruby_mastery static analysis (see OLLAMA_AGENT_RUBY_MASTERY)"
    def self_review
      dispatch_self_review_mode(SelfImprovement::Modes.normalize(options[:mode]))
    end

    desc "improve", "Shortcut for: self_review --mode automated"
    method_option :mode, type: :string, default: "automated",
                         desc: "Optional; must be automated (or 3, sandbox, full). Other modes: use self_review --mode"
    method_option :model, type: :string, desc: "Ollama model (default: OLLAMA_AGENT_MODEL or ollama-client default)"
    method_option :root, type: :string, desc: "Source tree to copy and test (default: OLLAMA_AGENT_ROOT or cwd)"
    method_option :timeout, type: :numeric, aliases: "-t", desc: "HTTP timeout seconds (default 120)"
    method_option :think, type: :string, desc: "Thinking mode: true|false|high|medium|low (see OLLAMA_AGENT_THINK)"
    method_option :yes, type: :boolean, aliases: "-y", desc: "Apply all patches without confirmation"
    method_option :semi, type: :boolean, default: true,
                         desc: "Without -y: auto-approve obvious patches; prompt for risky (default: true)"
    method_option :apply, type: :boolean, default: false,
                          desc: "After green tests, copy changed files from sandbox into --root"
    method_option :no_skills, type: :boolean, default: false,
                              desc: "Disable bundled prompt skills (same as OLLAMA_AGENT_SKILLS=0)"
    method_option :skill_paths, type: :string,
                                desc: "Extra .md paths or dirs, colon-separated; merged with OLLAMA_AGENT_SKILL_PATHS"
    method_option :stream, type: :boolean, default: false,
                           desc: "Stream tokens to terminal as they arrive (OLLAMA_AGENT_STREAM=1)"
    method_option :max_tokens, type: :numeric,
                               desc: "Context window budget (OLLAMA_AGENT_MAX_TOKENS)"
    method_option :context_summarize, type: :boolean, default: false,
                                      desc: "Summarize dropped context vs sliding window"
    method_option :verify, type: :string,
                           desc: "Comma-separated post-agent checks (default: rspec; env " \
                                 "OLLAMA_AGENT_IMPROVE_VERIFY). Steps: syntax, rubocop, rspec"
    method_option :no_ruby_mastery, type: :boolean, default: false,
                                    desc: "Skip prepending ruby_mastery static analysis (see OLLAMA_AGENT_RUBY_MASTERY)"
    def improve
      ensure_improve_mode_only_automated!
      dispatch_self_review_mode("automated")
    end

    private

    def run_ask!(query)
      if session_tui?
        start_tui_interactive { |up| build_agent(user_prompt: up, attach_stream: false) }
        return
      end

      interactive_or_single_shot!(query) { build_agent }
    end

    def run_orchestrate!(query)
      if session_tui?
        start_tui_interactive { |up| build_orchestrator_agent(user_prompt: up, attach_stream: false) }
        return
      end

      interactive_or_single_shot!(query) { build_orchestrator_agent }
    end

    def interactive_or_single_shot!(query)
      agent = yield

      if @session_interactive
        start_interactive(agent)
      elsif query
        run_single_shot_agent!(agent, query)
      else
        puts Console.error_line("Error: provide a QUERY or use --interactive")
        exit 1
      end
    end

    # Thor 1.5+ freezes +options+ after parse; keep effective flags on the instance.
    def apply_session_interactive_tui_flags!(query)
      interactive = options[:interactive]
      tui = options[:tui]
      if query.to_s.strip.empty? && !(interactive && !tui)
        interactive = true
        tui = true
      end
      @session_interactive = interactive
      @session_tui = tui
    end

    def session_tui?
      @session_interactive && @session_tui
    end

    def ensure_improve_mode_only_automated!
      m = SelfImprovement::Modes.normalize(options[:mode])
      return if m == "automated"

      warn Console.error_line(improve_mode_error_message(m))
      exit 1
    end

    def improve_mode_error_message(normalized_mode)
      return invalid_improve_mode_message unless SelfImprovement::Modes.valid?(normalized_mode)

      "Command \"improve\" only runs automated (sandbox) mode. For other modes use: " \
        "ollama_agent self_review --mode analysis | interactive"
    end

    def invalid_improve_mode_message
      "Invalid --mode for improve: use automated (or 3, sandbox, full). Got: #{options[:mode].inspect}"
    end

    def dispatch_self_review_mode(mode)
      validate_self_review_mode!(mode)
      send(:"run_mode_#{mode}")
    end

    def validate_self_review_mode!(mode)
      return if SelfImprovement::Modes.valid?(mode)

      warn Console.error_line(
        "Invalid --mode: use analysis, interactive, or automated (or 1, 2, 3). Got: #{options[:mode].inspect}"
      )
      exit 1
    end

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- stream + context kwargs exceed limits
    def run_mode_analysis
      agent = Agent.new(
        model: options[:model],
        root: resolved_root_for_self_review,
        read_only: true,
        confirm_patches: false,
        http_timeout: options[:timeout],
        think: options[:think],
        max_tokens: options[:max_tokens],
        context_summarize: options[:context_summarize],
        **skill_agent_options
      )
      attach_console_streamer(agent) if stream_enabled?
      preamble = ruby_mastery_preamble(resolved_root_for_self_review)
      SelfImprovement::Analyzer.new(agent).run(preamble: preamble)
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    def run_mode_interactive
      agent = Agent.new(**interactive_agent_keywords)
      attach_console_streamer(agent) if stream_enabled?
      preamble = ruby_mastery_preamble(resolved_root_for_self_review)
      SelfImprovement::Analyzer.new(agent).run(SelfImprovement::Analyzer::INTERACTIVE_PROMPT, preamble: preamble)
    end

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- context kwargs push over limit
    def interactive_agent_keywords
      semi = options[:semi] != false
      {
        model: options[:model],
        root: resolved_root_for_self_review,
        read_only: false,
        confirm_patches: !options[:yes],
        patch_policy: semi ? PatchRisk.method(:assess).to_proc : nil,
        http_timeout: options[:timeout],
        think: options[:think],
        max_tokens: options[:max_tokens],
        context_summarize: options[:context_summarize]
      }.merge(skill_agent_options)
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    def run_mode_automated
      result = SelfImprovement::Improver.new.run(**improve_run_options)
      report_improve_result(result)
    end

    def resolved_root_for_self_review
      raw = options[:root] || ENV.fetch("OLLAMA_AGENT_ROOT", nil)
      base = raw.to_s.strip.empty? ? Dir.pwd : raw
      File.expand_path(base)
    end

    def ruby_mastery_enabled?
      return false if options[:no_ruby_mastery]
      return false if ENV.fetch("OLLAMA_AGENT_RUBY_MASTERY", "1") == "0"

      true
    end

    def ruby_mastery_preamble(root)
      return nil unless ruby_mastery_enabled?

      SelfImprovement::RubyMasteryContext.markdown_section(root)
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- context kwargs push over limit
    def improve_run_options
      {
        model: options[:model],
        root: options[:root] || ENV.fetch("OLLAMA_AGENT_ROOT", nil),
        yes: options[:yes],
        semi: options[:semi] != false,
        apply: options[:apply],
        http_timeout: options[:timeout],
        think: options[:think],
        max_tokens: options[:max_tokens],
        context_summarize: options[:context_summarize],
        stream: stream_enabled?,
        verify: options[:verify],
        ruby_mastery: ruby_mastery_enabled?
      }.merge(skill_agent_options)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def report_improve_result(result)
      unless result[:success]
        warn Console.error_line("Tests failed in sandbox.")
        puts result[:test_output]
        exit 1
      end

      root = result[:source_root]
      puts "ollama_agent: tests passed in sandbox (#{root})"
      copied = result[:copied_to_source]
      report_improve_copied_files(copied, root)
      report_improve_merge_outcome(copied, root)
    end

    def report_improve_merge_outcome(copied, root)
      if options[:apply]
        puts "ollama_agent: no changed files to copy from sandbox" if copied.empty?
        return
      end

      puts "ollama_agent: sandbox was discarded — your project tree was not updated. " \
           "Re-run with --apply to merge sandbox changes into #{root} after a green run."
    end

    def report_improve_copied_files(copied, root)
      return if copied.empty?

      puts "ollama_agent: copied #{copied.size} file(s) to #{root}"
      copied.sort.each { |rel| puts "  #{rel}" }
    end

    # Build an Agent for the `ask` command.
    # Same root as `self_review` / interactive: cwd when unset (see README).
    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- session + orchestrator + audit kwargs exceed limits
    def build_agent(user_prompt: nil, attach_stream: true)
      orch  = orchestrator_mode?
      perms = resolved_permissions
      agent = Agent.new(
        model: options[:model],
        root: resolved_root_for_self_review,
        read_only: options[:read_only],
        confirm_patches: !options[:yes],
        http_timeout: options[:timeout],
        think: options[:think],
        orchestrator: orch,
        confirm_delegation: orch ? !options[:yes] : true,
        audit: options[:audit],
        max_retries: options[:max_retries],
        session_id: resolved_session_id,
        resume: options[:resume] || false,
        max_tokens: options[:max_tokens],
        context_summarize: options[:context_summarize],
        provider_name: options[:provider],
        permissions: perms,
        user_prompt: user_prompt,
        **skill_agent_options
      )
      attach_console_streamer(agent) if stream_enabled? && attach_stream
      agent
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    def resolved_permissions
      profile = options[:permissions]&.to_sym
      return nil unless profile

      Runtime::Permissions.new(profile: profile)
    rescue ArgumentError
      nil
    end

    def resolved_session_id
      return options[:session] if options[:session]
      return nil unless options[:resume]

      list = Session::Store.list(root: resolved_root_for_self_review)
      list.first&.session_id
    end

    def orchestrator_mode?
      return true if ENV.fetch("OLLAMA_AGENT_ORCHESTRATOR", "0").to_s == "1"

      ENV.fetch("OLLAMA_AGENT_MODE", "").to_s.strip.casecmp("orchestrator").zero?
    end

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- mirrors build_agent; stream attachment adds one line
    def build_orchestrator_agent(user_prompt: nil, attach_stream: true)
      agent = Agent.new(
        model: options[:model],
        root: resolved_root_for_self_review,
        read_only: options[:read_only],
        confirm_patches: !options[:yes],
        http_timeout: options[:timeout],
        think: options[:think],
        orchestrator: true,
        confirm_delegation: !options[:yes],
        audit: options[:audit],
        max_retries: options[:max_retries],
        max_tokens: options[:max_tokens],
        context_summarize: options[:context_summarize],
        user_prompt: user_prompt,
        **skill_agent_options
      )
      attach_console_streamer(agent) if stream_enabled? && attach_stream
      agent
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    def skill_agent_options
      out = {}
      out[:skills_enabled] = false if options[:no_skills]
      paths = PromptSkills.split_paths(options[:skill_paths])
      out[:skill_paths] = paths unless paths.empty?
      out
    end

    def stream_enabled?
      options[:stream] || ENV.fetch("OLLAMA_AGENT_STREAM", "0") == "1"
    end

    def attach_console_streamer(agent)
      Streaming::ConsoleStreamer.new.attach(agent.hooks)
    end

    def run_single_shot_agent!(agent, query)
      agent.run(query)
    rescue Ollama::Error, OllamaAgent::Error => e
      warn Console.error_line("#{e.class}: #{e.message}")
      exit 1
    rescue StandardError => e
      warn Console.error_line("#{e.class}: #{e.message}")
      warn e.full_message(order: :top, highlight: false) if ENV["OLLAMA_AGENT_DEBUG"] == "1"
      exit 1
    end

    def start_interactive(agent)
      CLI::Repl.new(agent: agent).start
    end

    def validate_tui_options!
      return unless @session_tui
      return if @session_interactive

      puts Console.error_line("Error: --tui requires --interactive (-i)")
      exit 1
    end

    def tui_god_mode?
      options[:tui_god] || ENV.fetch("OLLAMA_AGENT_TUI_GOD_MODE", "0") == "1"
    end

    def warn_if_tui_stream_conflict
      return unless stream_enabled?

      warn Console.error_line("ollama_agent: token streaming is disabled when using --tui.")
    end

    def start_tui_interactive
      require_relative "cli/tui_repl"
      warn_if_tui_stream_conflict
      tui = OllamaAgent::TUI.new(god_mode: tui_god_mode?)
      up = OllamaAgent::TuiUserPrompt.new(prompt: tui.prompt, stdout: $stdout)
      agent = yield(up)
      CLI::TuiRepl.new(agent: agent, tui: tui).start
    end

    def load_plugins!
      root = resolved_root_for_self_review
      Plugins::Loader.new(root: root).load_all(skip_gems: false)
    rescue StandardError => e
      warn "ollama_agent: plugin load error: #{e.message}" if ENV["OLLAMA_AGENT_DEBUG"] == "1"
    end
  end
  # rubocop:enable Metrics/ClassLength

  require_relative "cli/repl_shared"
  require_relative "cli/repl"
end

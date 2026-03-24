# frozen_string_literal: true

require "thor"

require_relative "agent"
require_relative "prompt_skills"

module OllamaAgent
  # Thor CLI for single-shot and interactive agent sessions.
  # rubocop:disable Metrics/ClassLength -- Thor commands and shared helpers
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "ask [QUERY]", "Run a natural-language task (reads, search, patch)"
    method_option :model, type: :string, desc: "Ollama model (default: OLLAMA_AGENT_MODEL or ollama-client default)"
    method_option :interactive, type: :boolean, aliases: "-i", desc: "Interactive REPL"
    method_option :yes, type: :boolean, aliases: "-y", desc: "Apply patches without confirmation"
    method_option :root, type: :string, desc: "Project root (default: OLLAMA_AGENT_ROOT or cwd)"
    method_option :timeout, type: :numeric, aliases: "-t", desc: "HTTP timeout seconds (default 120)"
    method_option :think, type: :string, desc: "Thinking mode: true|false|high|medium|low (see OLLAMA_AGENT_THINK)"
    method_option :no_skills, type: :boolean, default: false,
                              desc: "Disable bundled prompt skills (same as OLLAMA_AGENT_SKILLS=0)"
    method_option :skill_paths, type: :string,
                                desc: "Extra .md paths or dirs, colon-separated; merged with OLLAMA_AGENT_SKILL_PATHS"
    def ask(query = nil)
      agent = build_agent

      if options[:interactive]
        start_interactive(agent)
      elsif query
        agent.run(query)
      else
        puts Console.error_line("Error: provide a QUERY or use --interactive")
        exit 1
      end
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
    method_option :root, type: :string, desc: "Project root (default: OLLAMA_AGENT_ROOT or gem root)"
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
    def self_review
      dispatch_self_review_mode(SelfImprovement::Modes.normalize(options[:mode]))
    end

    desc "improve", "Shortcut for: self_review --mode automated"
    method_option :mode, type: :string, default: "automated",
                         desc: "Optional; must be automated (or 3, sandbox, full). Other modes: use self_review --mode"
    method_option :model, type: :string, desc: "Ollama model (default: OLLAMA_AGENT_MODEL or ollama-client default)"
    method_option :root, type: :string, desc: "Source tree to copy and test (default: OLLAMA_AGENT_ROOT or gem root)"
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
    def improve
      ensure_improve_mode_only_automated!
      dispatch_self_review_mode("automated")
    end

    private

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

    def run_mode_analysis
      agent = Agent.new(
        model: options[:model],
        root: resolved_root_for_self_review,
        read_only: true,
        confirm_patches: false,
        http_timeout: options[:timeout],
        think: options[:think],
        **skill_agent_options
      )
      SelfImprovement::Analyzer.new(agent).run
    end

    def run_mode_interactive
      agent = Agent.new(**interactive_agent_keywords)
      SelfImprovement::Analyzer.new(agent).run(SelfImprovement::Analyzer::INTERACTIVE_PROMPT)
    end

    def interactive_agent_keywords
      semi = options[:semi] != false
      {
        model: options[:model],
        root: resolved_root_for_self_review,
        read_only: false,
        confirm_patches: !options[:yes],
        patch_policy: semi ? PatchRisk.method(:assess).to_proc : nil,
        http_timeout: options[:timeout],
        think: options[:think]
      }.merge(skill_agent_options)
    end

    def run_mode_automated
      result = SelfImprovement::Improver.new.run(**improve_run_options)
      report_improve_result(result)
    end

    def resolved_root_for_self_review
      raw = options[:root] || ENV.fetch("OLLAMA_AGENT_ROOT", nil)
      base = raw.to_s.strip.empty? ? Dir.pwd : raw
      File.expand_path(base)
    end

    # rubocop:disable Metrics/AbcSize -- mirrors Improver.run keyword list
    def improve_run_options
      {
        model: options[:model],
        root: options[:root] || ENV.fetch("OLLAMA_AGENT_ROOT", nil),
        yes: options[:yes],
        semi: options[:semi] != false,
        apply: options[:apply],
        http_timeout: options[:timeout],
        think: options[:think]
      }.merge(skill_agent_options)
    end
    # rubocop:enable Metrics/AbcSize

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
      puts "ollama_agent: no changed files to copy from sandbox" if options[:apply] && copied.empty?
    end

    def report_improve_copied_files(copied, root)
      return if copied.empty?

      puts "ollama_agent: copied #{copied.size} file(s) to #{root}"
      copied.sort.each { |rel| puts "  #{rel}" }
    end

    # Build an Agent for the `ask` command.
    # Same root as `self_review` / interactive: cwd when unset (see README).
    def build_agent
      Agent.new(
        model: options[:model],
        root: resolved_root_for_self_review,
        confirm_patches: !options[:yes],
        http_timeout: options[:timeout],
        think: options[:think],
        **skill_agent_options
      )
    end

    def skill_agent_options
      out = {}
      out[:skills_enabled] = false if options[:no_skills]
      paths = PromptSkills.split_paths(options[:skill_paths])
      out[:skill_paths] = paths unless paths.empty?
      out
    end

    def start_interactive(agent)
      puts Console.welcome_banner("Ollama Agent (type 'exit' to quit)")
      use_readline = interactive_readline_usable?

      loop do
        input = interactive_readline_line(use_readline)
        break if input.nil?

        line = input.chomp
        break if line == "exit"

        agent.run(line)
      end
    end

    def interactive_readline_usable?
      require "readline"
      true
    rescue LoadError
      false
    end

    def interactive_readline_line(use_readline)
      if use_readline
        Readline.readline(Console.prompt_prefix, true)
      else
        print Console.prompt_prefix
        $stdin.gets
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end

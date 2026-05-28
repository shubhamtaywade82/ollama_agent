# frozen_string_literal: true

require "fileutils"
require_relative "version"
require_relative "tui_slash_reader"

require "tty-box"
require "tty-markdown"
require "tty-prompt"
require "tty-table"
require "tty-logger"
require "tty-screen"
require "pastel"

module OllamaAgent
  # Linear scrolling TUI for interactive agent sessions (TTY toolkit).
  # Avoids fixed multi-pane layouts; pairs with {CLI::TuiRepl}.
  # rubocop:disable Metrics/ClassLength -- façade over multiple tty-* components
  class TUI
    HISTORY_FILE = File.join(Dir.home, ".config", "ollama_agent", "repl_history")
    MAX_HISTORY  = 500

    attr_reader :prompt

    def initialize(stdout: $stdout, stderr: $stderr, logger: nil, god_mode: false)
      @stdout = stdout
      @stderr = stderr
      @god_mode = god_mode
      @prompt = TTY::Prompt.new(output: stdout, input: $stdin)
      @pastel = Pastel.new
      @logger = logger || TTY::Logger.new(output: stdout)
      @slash_reader = TuiSlashReader.new(
        completion_candidates: [],
        input: $stdin,
        output: @stdout,
        interrupt: :error
      )
      load_history
    end

    def render_dashboard(**options)
      config = options.fetch(:config)
      skills = options.fetch(:skills)
      scripts = options.fetch(:scripts) { [] }
      status = options.fetch(:status, "IDLE")
      budget = options[:budget]
      memory_line = options[:memory_line]
      table = build_context_table(config, skills, scripts, status, budget, memory_line)
      rendered_table = table.render(:unicode, padding: [0, 1])
      frame = box_frame(" Ollama Agent ", rendered_table)
      @stdout.puts "\n#{frame}\n"
    end

    # Render the three-panel providers dashboard: status, usage, routing decisions.
    #
    # @param pool_status      [Array<Hash>] from CredentialRouter#pool_status
    # @param routing_decisions [Array<String>] from CredentialRouter#routing_decisions
    # @param aggregate_usage  [Hash, nil]   from CredentialRouter#aggregate_usage
    def render_providers_dashboard(pool_status:, routing_decisions: [], aggregate_usage: nil)
      @stdout.puts "\n"
      @stdout.puts render_credential_status_box(pool_status)
      @stdout.puts render_usage_box(aggregate_usage || {})          if aggregate_usage
      @stdout.puts render_routing_decisions_box(routing_decisions)  unless routing_decisions.empty?
      @stdout.puts ""
    end

    def render_assistant_message(message)
      thinking = message.respond_to?(:thinking) ? message.thinking : nil
      content  = message.respond_to?(:content) ? message.content : message.to_s
      print_thinking_block(thinking) if thinking_present?(thinking)
      print_content_block(content) if content_present?(content)
      @stdout.puts @pastel.dim("-" * [TTY::Screen.width, 40].min)
    end

    def ask_interactive(question, options, god_mode: nil)
      return auto_pick_first(options) if god_mode.nil? ? @god_mode : god_mode

      @stdout.puts ""
      @prompt.select(
        @pastel.yellow.bold("Action required: ") + question.to_s,
        options,
        cycle: true,
        filter: true,
        per_page: 10
      )
    end

    def ask_user_input
      @prompt.ask(@pastel.green.bold("❯")) { |q| q.required true }
    rescue TTY::Reader::InputInterrupt
      nil
    end

    # Line editor with Tab completion for lines starting with +/+ (uses {TuiSlashReader}).
    #
    # @param completion_candidates [Array<String>] e.g. +/help+, +/model+; empty falls back to {TTY::Prompt#ask}.
    # @return [String, nil]
    def ask_user_line(completion_candidates: [], command_palette: nil)
      prompt = @pastel.green.bold("❯ ")
      @slash_reader.completion_candidates = Array(completion_candidates).uniq.sort
      @slash_reader.command_palette = command_palette
      line = @slash_reader.read_line(prompt).to_s
      save_history
      line
    rescue TTY::Reader::InputInterrupt
      nil
    end

    def log(level, message)
      case level
      when :info  then @logger.info(message)
      when :warn  then @logger.warn(message)
      when :error then @logger.error(message)
      else
        @logger.debug(message)
      end
    end

    def print_error(message)
      @stderr.puts @pastel.red(message.to_s)
    end

    def goodbye
      @stdout.puts "\n#{@pastel.dim("Goodbye.")}"
    end

    private

    def load_history
      return unless File.exist?(HISTORY_FILE)

      hist = @slash_reader.instance_variable_get(:@history)
      return unless hist

      hist.clear
      File.readlines(HISTORY_FILE, chomp: true).last(MAX_HISTORY).each do |line|
        next if line.strip.empty?

        hist << line
      end
    rescue StandardError
      nil
    end

    def save_history
      hist = @slash_reader.instance_variable_get(:@history)
      return unless hist

      dir = File.dirname(HISTORY_FILE)
      FileUtils.mkdir_p(dir)
      File.write(HISTORY_FILE, hist.to_a.last(MAX_HISTORY).join("\n"))
    rescue StandardError
      nil
    end

    def status_row(status)
      s = status.to_s
      return @pastel.green(s) if s.casecmp("ACTIVE").zero?

      @pastel.yellow(s)
    end

    def append_budget_rows(table, budget)
      return unless budget

      h = budget.to_h
      table << ["Steps", "#{h[:steps]} / #{h[:max_steps]}"]
      table << ["Tokens", "#{h[:tokens_used]} / #{h[:max_tokens]}"]
      return unless h[:cost_usd].to_f.positive?

      table << ["Cost", format("$%.4f", h[:cost_usd])]
    end

    # rubocop:disable Metrics/ParameterLists -- row keys are fixed dashboard columns
    def build_context_table(config, skills, scripts, status, budget, memory_line)
      table = TTY::Table.new(header: [@pastel.bold("Key"), @pastel.bold("Value")])
      table << ["Model", config.fetch(:model, "unknown")]
      table << ["Endpoint", config.fetch(:endpoint, "default")]
      table << ["Skills", skills]
      table << ["Scripts", scripts.empty? ? "(none)" : scripts.join(", ")]
      table << ["Status", status_row(status)]
      append_budget_rows(table, budget)
      table << ["Memory", memory_line] if memory_line
      table
    end
    # rubocop:enable Metrics/ParameterLists

    def box_frame(title, inner)
      ver = " v#{OllamaAgent::VERSION} "
      TTY::Box.frame(
        width: [TTY::Screen.width, 40].max,
        title: { top_left: title, bottom_right: ver },
        border: :thick,
        style: { border: { fg: :blue } }
      ) { inner }
    end

    def thinking_present?(thinking)
      thinking && !thinking.to_s.strip.empty?
    end

    def content_present?(content)
      content && !content.to_s.strip.empty?
    end

    def print_thinking_block(thinking)
      @stdout.puts "\n#{@pastel.magenta.bold("Thinking")}\n"
      @stdout.puts @pastel.dim(thinking.to_s.rstrip)
    end

    def print_content_block(content)
      @stdout.puts "\n#{@pastel.green.bold("Assistant")}\n"
      @stdout.puts TTY::Markdown.parse(content.to_s)
    rescue StandardError
      @stdout.puts content.to_s
    end

    def auto_pick_first(options)
      first = options.first
      return first[:value] if first.is_a?(Hash) && first.key?(:value)

      first
    end

    # ── Providers dashboard helpers ─────────────────────────────────────

    def render_credential_status_box(pool_status)
      table = TTY::Table.new(header: [
        @pastel.bold("Credential"),
        @pastel.bold("Provider"),
        @pastel.bold("Status"),
        @pastel.bold("Quota")
      ])

      pool_status.each do |cred|
        table << [
          cred[:name] || cred[:id],
          cred[:provider],
          credential_status_label(cred),
          quota_bar(cred.dig(:quota, :daily_pct))
        ]
      end

      inner = table.render(:unicode, padding: [0, 1]) || "(no credentials configured)"
      TTY::Box.frame(
        width: [TTY::Screen.width, 50].max,
        title: { top_left: " Providers " },
        border: :thick,
        style: { border: { fg: :cyan } }
      ) { inner }
    end

    def render_usage_box(usage)
      lines = []
      lines << format_usage_line("RPM",          usage[:total_rpm],            nil)
      lines << format_usage_line("TPM",          usage[:total_tpm],            nil)
      lines << format_usage_line("Daily tokens", usage[:total_daily_tokens],   nil)
      lines << format_usage_line("Daily reqs",   usage[:total_daily_requests], nil)

      TTY::Box.frame(
        width: [TTY::Screen.width, 50].max,
        title: { top_left: " Usage " },
        border: :thick,
        style: { border: { fg: :blue } }
      ) { lines.join("\n") }
    end

    def render_routing_decisions_box(decisions)
      inner = decisions.last(8).join("\n")
      TTY::Box.frame(
        width: [TTY::Screen.width, 50].max,
        title: { top_left: " Recent Routing " },
        border: :thick,
        style: { border: { fg: :magenta } }
      ) { inner }
    end

    def credential_status_label(cred)
      if cred[:disabled]
        @pastel.red("🔴 disabled")
      elsif cred[:cooling_down]
        secs = cred[:cooldown_secs].to_i
        @pastel.yellow("💤 cool #{secs}s")
      elsif cred[:near_exhaustion]
        pct = (cred.dig(:quota, :daily_pct).to_f * 100).round
        @pastel.yellow("⚠️  #{pct}% quota")
      elsif cred[:available]
        @pastel.green("✅ healthy")
      else
        @pastel.red("❌ unavailable")
      end
    end

    def quota_bar(pct)
      return @pastel.dim("n/a") unless pct && pct.positive?

      filled = (pct * 10).round.clamp(0, 10)
      bar    = ("█" * filled) + ("░" * (10 - filled))
      label  = "#{(pct * 100).round}%"
      color  = pct >= 0.9 ? :red : pct >= 0.7 ? :yellow : :green
      @pastel.send(color, "#{bar} #{label}")
    end

    def format_usage_line(label, value, limit)
      val_str = value ? value.to_s : "—"
      lim_str = limit ? " / #{limit}" : ""
      "  #{@pastel.bold(label.ljust(14))} #{val_str}#{lim_str}"
    end
  end
  # rubocop:enable Metrics/ClassLength
end

# frozen_string_literal: true

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
    attr_reader :prompt

    def initialize(stdout: $stdout, stderr: $stderr, logger: nil, god_mode: false)
      @stdout = stdout
      @stderr = stderr
      @god_mode = god_mode
      @prompt = TTY::Prompt.new(output: stdout, input: $stdin)
      @pastel = Pastel.new
      @logger = logger || TTY::Logger.new(output: stdout)
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
    # rubocop:disable Metrics/MethodLength -- prompt ask vs reader branch
    def ask_user_line(completion_candidates: [])
      if completion_candidates.nil? || completion_candidates.empty?
        return @prompt.ask(@pastel.green.bold("❯")) { |q| q.required true }
      end

      prompt = @pastel.green.bold("❯ ")
      reader = TuiSlashReader.new(
        completion_candidates: completion_candidates,
        input: $stdin,
        output: @stdout,
        interrupt: :error
      )
      reader.read_line(prompt).to_s
    rescue TTY::Reader::InputInterrupt
      nil
    end
    # rubocop:enable Metrics/MethodLength

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
  end
  # rubocop:enable Metrics/ClassLength
end

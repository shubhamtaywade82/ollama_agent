# frozen_string_literal: true

require "fileutils"

require_relative "repl_shared"

module OllamaAgent
  class CLI
    # Interactive REPL for the agent.
    #
    # Features:
    #   - Slash commands (/help, /model, /models, /session, /memory, /status, /clear, /config, /provider, /index)
    #   - Readline history with persistent file
    #   - Multi-line input (end with blank line)
    #   - Session resume inside REPL
    #   - Token budget and loop-detector status display
    #   - Graceful Ctrl-C and Ctrl-D handling
    # rubocop:disable Metrics/ClassLength -- readline wiring + banner + history
    class Repl
      include ReplShared

      HISTORY_FILE = File.join(Dir.home, ".config", "ollama_agent", "repl_history")
      MAX_HISTORY  = 500

      PROMPT = "\e[32mollama\e[0m \e[90m›\e[0m "

      def initialize(agent:, memory: nil, budget: nil, stdout: $stdout, stderr: $stderr)
        @agent   = agent
        @memory  = memory
        @budget  = budget
        @stdout  = stdout
        @stderr  = stderr
        @running = false
      end

      # rubocop:disable Metrics/MethodLength -- readline loop + history ensure
      def start
        @running = true
        setup_readline
        print_banner

        loop do
          input = read_line
          break if input.nil?

          line = input.chomp.strip
          next if line.empty?

          break if %w[/exit exit].include?(line)

          if line.start_with?("/")
            handle_slash(line)
          else
            run_query(line)
          end
        end

        @stdout.puts "\n\e[90mGoodbye.\e[0m"
      ensure
        save_history
      end
      # rubocop:enable Metrics/MethodLength

      private

      def setup_readline
        return unless readline_available?

        load_history
        Readline.completion_proc = slash_completer
        configure_readline_slash_completion
      end

      # Shows command hints: type `/` then Tab (lists matches) or Tab again to cycle.
      # With GNU Readline, `autocompletion` can show inline candidates while typing.
      def configure_readline_slash_completion
        Readline.completion_append_character = "" if Readline.respond_to?(:completion_append_character=)
        Readline.autocompletion = true if Readline.respond_to?(:autocompletion=)
      end

      def slash_completer
        proc do |input|
          slash_completer_candidates.select { |cmd| cmd.start_with?(input.to_s) }
        end
      end

      def read_line
        if readline_available?
          Readline.readline(PROMPT, true)
        else
          @stdout.print PROMPT
          @stdout.flush
          $stdin.gets
        end
      rescue Interrupt
        @stdout.puts ""
        ""
      end

      def readline_available?
        return @readline_available unless @readline_available.nil?

        @readline_available = (require "readline") && true
      rescue LoadError
        @readline_available = false
      end

      def run_query(query)
        @agent.run(query)
      rescue OllamaAgent::Error => e
        @stderr.puts "\e[31mError: #{e.message}\e[0m"
      rescue StandardError => e
        @stderr.puts "\e[31m#{e.class}: #{e.message}\e[0m"
        @stderr.puts e.backtrace.first(5).join("\n") if ENV["OLLAMA_AGENT_DEBUG"] == "1"
      end

      # rubocop:disable Metrics/MethodLength -- ASCII banner lines
      def print_banner
        @stdout.puts "\e[1m\e[34m"
        @stdout.puts "  ██████╗ ██╗     ██╗      █████╗ ███╗   ███╗ █████╗ "
        @stdout.puts "  ██╔═══██╗██║     ██║     ██╔══██╗████╗ ████║██╔══██╗"
        @stdout.puts "  ██║   ██║██║     ██║     ███████║██╔████╔██║███████║"
        @stdout.puts "  ██║   ██║██║     ██║     ██╔══██║██║╚██╔╝██║██╔══██║"
        @stdout.puts "  ╚██████╔╝███████╗███████╗██║  ██║██║ ╚═╝ ██║██║  ██║"
        @stdout.puts "   ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝"
        @stdout.puts "\e[0m"
        @stdout.puts "  Universal AI operator runtime  •  type \e[33m/help\e[0m for commands"
        print_slash_completion_hint if readline_available?
        @stdout.puts ""
      end
      # rubocop:enable Metrics/MethodLength

      def print_slash_completion_hint
        @stdout.puts "  \e[33m/\e[0m then \e[33mTab\e[0m — slash-command hints; Tab again to list all matches"
      end

      def load_history
        return unless File.exist?(HISTORY_FILE)

        File.readlines(HISTORY_FILE, chomp: true).last(MAX_HISTORY).each do |line|
          Readline::HISTORY.push(line)
        end
      rescue StandardError
        nil
      end

      def save_history
        return unless readline_available?

        dir = File.dirname(HISTORY_FILE)
        FileUtils.mkdir_p(dir)
        File.write(HISTORY_FILE, Readline::HISTORY.to_a.last(MAX_HISTORY).join("\n"))
      rescue StandardError
        nil
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

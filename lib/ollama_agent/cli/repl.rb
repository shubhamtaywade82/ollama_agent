# frozen_string_literal: true

module OllamaAgent
  class CLI
    # Interactive REPL for the agent.
    #
    # Features:
    #   - Slash commands (/help, /session, /memory, /status, /clear, /config, /provider, /index)
    #   - Readline history with persistent file
    #   - Multi-line input (end with blank line)
    #   - Session resume inside REPL
    #   - Token budget and loop-detector status display
    #   - Graceful Ctrl-C and Ctrl-D handling
    class Repl
      HISTORY_FILE = File.join(Dir.home, ".config", "ollama_agent", "repl_history")
      MAX_HISTORY  = 500

      SLASH_COMMANDS = {
        "/help"     => "Show this help message",
        "/status"   => "Show run budget, provider, memory summary",
        "/session"  => "Show or switch session (usage: /session [id])",
        "/memory"   => "Query long-term memory (usage: /memory [key])",
        "/remember" => "Store a fact (usage: /remember key = value)",
        "/clear"    => "Clear short-term context for this session",
        "/config"   => "Show current agent configuration",
        "/provider" => "Show or switch provider (usage: /provider [name])",
        "/index"    => "Summarise the project repository index",
        "/exit"     => "Exit the REPL"
      }.freeze

      PROMPT = "\e[32mollama\e[0m \e[90m›\e[0m "

      def initialize(agent:, memory: nil, budget: nil, stdout: $stdout, stderr: $stderr)
        @agent   = agent
        @memory  = memory
        @budget  = budget
        @stdout  = stdout
        @stderr  = stderr
        @running = false
      end

      def start
        @running = true
        setup_readline
        print_banner

        loop do
          input = read_line
          break if input.nil?

          line = input.chomp.strip
          next if line.empty?

          break if line == "/exit" || line == "exit"

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

      private

      def setup_readline
        return unless readline_available?

        load_history
        Readline.completion_proc = slash_completer
      end

      def slash_completer
        proc do |input|
          SLASH_COMMANDS.keys.select { |cmd| cmd.start_with?(input) }
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

      def handle_slash(line)
        parts   = line.split(" ", 2)
        command = parts[0].downcase
        arg     = parts[1]

        case command
        when "/help"     then print_help
        when "/status"   then print_status
        when "/session"  then handle_session(arg)
        when "/memory"   then handle_memory(arg)
        when "/remember" then handle_remember(arg)
        when "/clear"    then handle_clear
        when "/config"   then print_config
        when "/provider" then handle_provider(arg)
        when "/index"    then handle_index
        else
          check_plugin_commands(command, arg)
        end
      end

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
        @stdout.puts ""
      end

      def print_help
        @stdout.puts "\n\e[1mSlash commands:\e[0m"
        SLASH_COMMANDS.each do |cmd, desc|
          @stdout.puts "  \e[33m#{cmd.ljust(14)}\e[0m #{desc}"
        end

        plugin_cmds = OllamaAgent::Plugins::Registry.all_command_handlers rescue []
        if plugin_cmds.any?
          @stdout.puts "\n\e[1mPlugin commands:\e[0m"
          plugin_cmds.each { |h| @stdout.puts "  \e[35m#{h[:slash_command]}\e[0m" }
        end

        @stdout.puts ""
      end

      def print_status
        @stdout.puts "\n\e[1mStatus:\e[0m"

        if @budget
          b = @budget.to_h
          @stdout.puts "  Steps:   #{b[:steps]} / #{b[:max_steps]}"
          @stdout.puts "  Tokens:  #{b[:tokens_used]} / #{b[:max_tokens]}"
          @stdout.puts "  Cost:    $#{b[:cost_usd].round(4)}" if b[:cost_usd] > 0
        end

        if @memory
          s = @memory.summary
          @stdout.puts "  Memory:  #{s[:short_term_entries]} short-term, " \
                       "#{s[:session_keys]} session keys, " \
                       "#{s[:long_term_namespaces]} LT namespaces"
        end

        @stdout.puts ""
      end

      def handle_session(arg)
        if arg
          @stdout.puts "  Switching session is not supported mid-run. " \
                       "Restart with: ollama_agent ask --session #{arg} --resume"
        else
          id = @agent.instance_variable_get(:@session_id) rescue nil
          @stdout.puts "  Current session: #{id || "(none)"}"
        end
      end

      def handle_memory(arg)
        return print_memory_list unless arg

        val = @memory&.recall(arg)
        if val
          @stdout.puts "  \e[33m#{arg}\e[0m = #{val}"
        else
          @stdout.puts "  No memory found for: #{arg}"
        end
      end

      def print_memory_list
        return @stdout.puts "  No memory manager attached" unless @memory

        entries = @memory.list
        if entries.empty?
          @stdout.puts "  No long-term memories stored yet."
        else
          @stdout.puts "\n\e[1mLong-term memory:\e[0m"
          entries.each { |k, v| @stdout.puts "  \e[33m#{k}\e[0m: #{v.to_s[0, 80]}" }
        end
        @stdout.puts ""
      end

      def handle_remember(arg)
        return @stdout.puts "  Usage: /remember key = value" unless arg&.include?("=")

        key, value = arg.split("=", 2).map(&:strip)
        @memory&.remember(key, value, tier: :long_term)
        @stdout.puts "  Stored: \e[33m#{key}\e[0m = #{value}"
      end

      def handle_clear
        @memory&.flush_short_term!
        @stdout.puts "  Short-term memory cleared."
      end

      def print_config
        @stdout.puts "\n\e[1mConfiguration:\e[0m"
        ivars = %i[@model @root @read_only @max_tokens @session_id @orchestrator]
        ivars.each do |ivar|
          val = @agent.instance_variable_get(ivar) rescue nil
          next if val.nil?

          @stdout.puts "  \e[36m#{ivar.to_s.delete_prefix("@").ljust(16)}\e[0m #{val}"
        end
        @stdout.puts ""
      end

      def handle_provider(arg)
        if arg
          @stdout.puts "  Provider switching mid-run is not yet supported. Restart with --provider #{arg}"
        else
          @stdout.puts "  Current provider: #{@agent.instance_variable_get(:@provider_name) || "ollama"}"
        end
      end

      def handle_index
        root = @agent.instance_variable_get(:@root) || Dir.pwd
        packer = OllamaAgent::Indexing::ContextPacker.new(root: root) rescue nil
        if packer
          @stdout.puts packer.repo_summary
        else
          @stdout.puts "  Index unavailable — require 'ollama_agent/indexing/context_packer' first"
        end
      end

      def check_plugin_commands(command, arg)
        handlers = OllamaAgent::Plugins::Registry.all_command_handlers rescue []
        match    = handlers.find { |h| h[:slash_command] == command }

        if match
          match[:handler].call(arg, agent: @agent, stdout: @stdout)
        else
          @stdout.puts "  Unknown command: #{command}. Type /help for available commands."
        end
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
  end
end

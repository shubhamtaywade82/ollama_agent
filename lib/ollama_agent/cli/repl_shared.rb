# frozen_string_literal: true

module OllamaAgent
  class CLI
    # Slash-command handlers shared by {Repl} and {TuiRepl}.
    # rubocop:disable Metrics/ModuleLength, Layout/HashAlignment, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/MethodLength, Style/RescueModifier, Style/NumericPredicate -- legacy Repl extraction
    module ReplShared
      SLASH_COMMANDS = {
        "/help"     => "Show this help message",
        "/status"   => "Show run budget, provider, memory summary",
        "/session"  => "Show or switch session (usage: /session [id])",
        "/memory"   => "Query long-term memory (usage: /memory [key])",
        "/remember" => "Store a fact (usage: /remember key = value)",
        "/clear"    => "Clear short-term context for this session",
        "/config"   => "Show current agent configuration",
        "/model"    => "Show or set chat model (usage: /model [name] | /model list)",
        "/models"   => "List Ollama cloud catalog (ollama.com/api/tags); /model <name> to switch",
        "/provider" => "Show or switch provider (usage: /provider [name])",
        "/index"    => "Summarise the project repository index",
        "/exit"     => "Exit the REPL"
      }.freeze

      private

      def repl_memory
        @memory || @agent.instance_variable_get(:@memory_manager)
      end

      def repl_budget
        @budget || @agent.instance_variable_get(:@budget)
      end

      def slash_completer_candidates
        base = SLASH_COMMANDS.keys
        extras = plugin_slash_command_strings
        (base + extras).uniq.sort
      end

      def plugin_slash_command_strings
        OllamaAgent::Plugins::Registry.all_command_handlers.map { |h| h[:slash_command].to_s }
      rescue StandardError
        []
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
        when "/model"    then handle_model(arg)
        when "/models"   then print_model_list
        when "/provider" then handle_provider(arg)
        when "/index"    then handle_index
        else
          check_plugin_commands(command, arg)
        end
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
        @stdout.puts "  Model:   #{@agent.model}"

        if (b = repl_budget)
          h = b.to_h
          @stdout.puts "  Steps:   #{h[:steps]} / #{h[:max_steps]}"
          @stdout.puts "  Tokens:  #{h[:tokens_used]} / #{h[:max_tokens]}"
          @stdout.puts "  Cost:    $#{h[:cost_usd].round(4)}" if h[:cost_usd] > 0
        end

        mem = repl_memory
        if mem
          s = mem.summary
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

        mem = repl_memory
        val = mem&.recall(arg)
        if val
          @stdout.puts "  \e[33m#{arg}\e[0m = #{val}"
        else
          @stdout.puts "  No memory found for: #{arg}"
        end
      end

      def print_memory_list
        mem = repl_memory
        return @stdout.puts "  No memory manager attached" unless mem

        entries = mem.list
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

        mem = repl_memory
        key, value = arg.split("=", 2).map(&:strip)
        mem&.remember(key, value, tier: :long_term)
        @stdout.puts "  Stored: \e[33m#{key}\e[0m = #{value}"
      end

      def handle_clear
        repl_memory&.flush_short_term!
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
          @stdout.puts "  Chat model can be changed anytime: /model <name>"
        else
          @stdout.puts "  Current provider: #{@agent.instance_variable_get(:@provider_name) || "ollama"}"
        end
      end

      def handle_model(arg)
        return print_current_model if arg.nil? || arg.strip.empty?

        if arg.strip.casecmp("list").zero?
          print_model_list
          return
        end

        name = @agent.assign_chat_model!(arg)
        @stdout.puts "  Chat model set to: #{name}"
      rescue OllamaAgent::Error => e
        @stdout.puts "  #{e.message}"
      end

      def print_current_model
        @stdout.puts "  Current chat model: #{@agent.model}"
      end

      def print_model_list
        names = @agent.list_cloud_model_names
        if names.empty?
          @stdout.puts "  Could not load the cloud model catalog (network or ollama.com)."
          @stdout.puts "  Set OLLAMA_API_KEY if your account requires it; or set /model <name> manually."
          return
        end

        @stdout.puts "\n\e[1mOllama cloud models (ollama.com/api/tags):\e[0m"
        names.each { |n| @stdout.puts "  #{n}" }
        @stdout.puts ""
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
    end
    # rubocop:enable Metrics/ModuleLength, Layout/HashAlignment, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/MethodLength, Style/RescueModifier, Style/NumericPredicate
  end
end

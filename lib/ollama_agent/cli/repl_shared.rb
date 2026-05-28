# frozen_string_literal: true

module OllamaAgent
  class CLI
    # Slash-command handlers shared by {Repl} and {TuiRepl}.
    # rubocop:disable Metrics/ModuleLength, Layout/HashAlignment, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/MethodLength, Style/NumericPredicate -- REPL command dispatch
    module ReplShared
      SLASH_COMMANDS = {
        "/help"     => "Show this help message",
        "/status"   => "Show run budget, provider, memory summary",
        "/session"  => "Show or switch session (usage: /session [id])",
        "/memory"   => "Query long-term memory (usage: /memory [key])",
        "/remember" => "Store a fact (usage: /remember key = value)",
        "/clear"    => "Clear short-term context for this session",
        "/config"   => "Show current agent configuration",
        "/model"    => "Show or set chat model (usage: /model [name])",
        "/models"   => "List available models and capabilities (usage: /models [filter])",
        "/provider" => "Show or switch provider (usage: /provider [name])",
        "/index"    => "Summarise the project repository index",
        "/exit"     => "Exit the REPL"
      }.freeze

      private

      def repl_debug?
        ENV["OLLAMA_AGENT_DEBUG"] == "1"
      end

      def repl_warn_swallowed(context, error)
        return unless repl_debug?

        warn "ollama_agent: #{context}: #{error.class}: #{error.message}"
      end

      def safe_plugin_command_handlers
        OllamaAgent::Plugins::Registry.all_command_handlers
      rescue StandardError => e
        repl_warn_swallowed("plugin command handlers", e)
        []
      end

      def build_repo_index_packer
        OllamaAgent::Indexing::ContextPacker.new(root: @agent.root)
      rescue StandardError => e
        repl_warn_swallowed("repository index packer", e)
        nil
      end

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
        safe_plugin_command_handlers.map { |h| h[:slash_command].to_s }
      end

      def runtime_command_palette
        require_relative "../runtime_command_system/command_palette"

        commands = SLASH_COMMANDS.merge(plugin_slash_command_strings.to_h { |cmd| [cmd, "Plugin command"] })
        OllamaAgent::RuntimeCommandSystem::CommandPalette.new(
          commands: commands,
          session: { agent: @agent }
        )
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
        when "/models"   then print_model_list(arg)
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

        plugin_cmds = safe_plugin_command_handlers
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
          id = @agent.session_id
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
        rows = [
          [:model, @agent.model],
          [:root, @agent.root],
          [:read_only, @agent.read_only],
          [:max_tokens, @agent.max_tokens],
          [:session_id, @agent.session_id],
          [:orchestrator, @agent.orchestrator]
        ]
        rows.each do |label, val|
          next if val.nil?

          @stdout.puts "  \e[36m#{label.to_s.ljust(16)}\e[0m #{val}"
        end
        @stdout.puts ""
      end

      def handle_provider(arg)
        if arg
          @stdout.puts "  Provider switching mid-run is not yet supported. Restart with --provider #{arg}"
          @stdout.puts "  Chat model can be changed anytime: /model <name>"
        else
          @stdout.puts "  Current provider: #{@agent.provider_name || "ollama"}"
        end
      end

      def handle_model(arg)
        return print_current_model if arg.nil? || arg.strip.empty?

        parts = arg.strip.split(" ", 2)
        subcommand = parts[0]
        filter = parts[1]

        if subcommand.casecmp("list").zero?
          print_model_list(filter)
          return
        end

        require_relative "../providers/model_registry"
        descriptor = OllamaAgent::Providers::ModelRegistry.find(subcommand, agent: @agent)

        if descriptor
          if !descriptor.tools?
            @stdout.puts "  \e[33mWarning: Model '#{descriptor.name}' does not list tool calling capabilities.\e[0m"
            @stdout.puts "  Agentic tools (e.g. edit_file, diffs) may not work correctly."
          end

          current_model_desc = OllamaAgent::Providers::ModelRegistry.find(@agent.model, agent: @agent)
          if current_model_desc && descriptor.context_size < current_model_desc.context_size
            @stdout.puts "  \e[33mWarning: Context size is shrinking from #{current_model_desc.context_size} to #{descriptor.context_size}.\e[0m"
            @stdout.puts "  Older messages may be truncated or summarized."
          end
        else
          @stdout.puts "  \e[33mWarning: Model '#{subcommand}' not found in registry. Switching anyway...\e[0m"
        end

        name = @agent.assign_chat_model!(subcommand)
        @stdout.puts "  ✓ Chat model switched to: \e[1;32m#{name}\e[0m"
      rescue OllamaAgent::Error => e
        @stdout.puts "  #{e.message}"
      end

      def print_current_model
        @stdout.puts "  Current chat model: #{@agent.model}"
      end

      def print_model_list(filter = nil)
        require_relative "../providers/model_registry"
        models = OllamaAgent::Providers::ModelRegistry.all(agent: @agent)

        if filter && !filter.strip.empty?
          query = filter.strip.downcase
          if query == "--vision"
            models.select!(&:vision?)
          elsif query == "--tools"
            models.select!(&:tools?)
          elsif query == "--local"
            models.select! { |m| m.provider == "local" }
          elsif query == "--loaded"
            models.select! { |m| m.status == "loaded" }
          else
            models.select! { |m| m.name.downcase.include?(query) || m.provider.downcase.include?(query) }
          end
        end

        if models.empty?
          @stdout.puts "  No models matching '#{filter}' found."
          return
        end

        grouped = models.group_by(&:provider)

        @stdout.puts "\n\e[1mRegistered Inference Models:\e[0m"
        grouped.each do |provider, list|
          @stdout.puts "\n  \e[1;36m#{provider.upcase}\e[0m"
          @stdout.puts "  " + "─" * 60
          list.each do |m|
            is_current = m.name.casecmp(@agent.model.to_s).zero?
            marker = is_current ? " \e[32m● (current)\e[0m" : ""

            caps = ["chat"]
            caps << "tools" if m.tools?
            caps << "vision" if m.vision?
            caps << "reasoning" if m.reasoning?

            size_info = m.size_gb ? " [#{m.size_gb} GB]" : ""
            status_info = m.status == "loaded" ? " \e[90m(loaded)\e[0m" : ""

            @stdout.puts "    \e[1m#{m.name.ljust(30)}\e[0m | ctx: #{m.context_size.to_s.ljust(6)} | caps: #{caps.join(",")}#{size_info}#{status_info}#{marker}"
          end
        end
        @stdout.puts ""
      end

      def handle_index
        packer = build_repo_index_packer
        if packer
          @stdout.puts packer.repo_summary
        else
          @stdout.puts "  Index unavailable (set OLLAMA_AGENT_DEBUG=1 for details on stderr)"
        end
      end

      def check_plugin_commands(command, arg)
        handlers = safe_plugin_command_handlers
        match    = handlers.find { |h| h[:slash_command] == command }

        if match
          match[:handler].call(arg, agent: @agent, stdout: @stdout)
        else
          @stdout.puts "  Unknown command: #{command}. Type /help for available commands."
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength, Layout/HashAlignment, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/MethodLength, Style/NumericPredicate
  end
end

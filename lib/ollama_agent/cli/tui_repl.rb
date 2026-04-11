# frozen_string_literal: true

require_relative "../tui"
require_relative "../tui_user_prompt"
require_relative "repl_shared"

module OllamaAgent
  class CLI
    # Interactive REPL using TTY toolkit (box, table, markdown, prompt).
    # rubocop:disable Metrics/ClassLength -- session loop + dashboard + agent wiring
    class TuiRepl
      include ReplShared

      # rubocop:disable Metrics/ParameterLists -- mirrors {Repl} IO + optional memory injection
      def initialize(agent:, tui:, stdout: $stdout, stderr: $stderr, memory: nil, budget: nil)
        @agent = agent
        @tui = tui
        @stdout = stdout
        @stderr = stderr
        @memory = memory
        @budget = budget
        @assistant_hook_installed = false
      end
      # rubocop:enable Metrics/ParameterLists

      # rubocop:disable Metrics/MethodLength -- straight-line session loop
      def start
        show_boot_dashboard
        @tui.log(:info, "Session ready — type / then Tab to complete slash commands; /help lists all.")

        loop do
          line = read_user_line
          break if line.nil?

          line = line.to_s.chomp.strip
          next if line.empty?

          break if %w[/exit exit].include?(line)

          if line.start_with?("/")
            dispatch_slash(line)
          else
            run_agent_query(line)
          end
        end

        @tui.goodbye
      end
      # rubocop:enable Metrics/MethodLength

      private

      def read_user_line
        @tui.ask_user_line(completion_candidates: slash_completer_candidates)
      rescue Interrupt
        nil
      end

      def dispatch_slash(line)
        if line == "/status"
          show_context_dashboard
          return
        end

        handle_slash(line)
      end

      # rubocop:disable Metrics/MethodLength -- capture hook + errors + ensure
      def run_agent_query(query)
        ensure_assistant_hook
        @capture_assistant = true
        @pending_messages  = []
        @agent.run(query)
        flush_assistant_messages
      rescue OllamaAgent::Error => e
        @tui.print_error("Error: #{e.message}")
      rescue StandardError => e
        @tui.print_error("#{e.class}: #{e.message}")
        @tui.print_error(e.backtrace.first(5).join("\n")) if ENV["OLLAMA_AGENT_DEBUG"] == "1"
      ensure
        @capture_assistant = false
      end
      # rubocop:enable Metrics/MethodLength

      def ensure_assistant_hook
        return if @assistant_hook_installed

        @agent.hooks.on(:on_assistant_message) do |payload|
          @pending_messages << payload[:message] if @capture_assistant
        end
        @assistant_hook_installed = true
      end

      def flush_assistant_messages
        @pending_messages.each { |m| @tui.render_assistant_message(m) }
        @pending_messages.clear
      end

      def show_boot_dashboard
        show_context_dashboard
      end

      # rubocop:disable Metrics/MethodLength -- single dashboard assembly call
      def show_context_dashboard
        skills = skills_summary_for_agent
        scripts = scripts_placeholder
        mem_line = memory_summary_line
        @tui.render_dashboard(
          config: dashboard_config_hash,
          skills: skills,
          scripts: scripts,
          status: "ACTIVE",
          budget: repl_budget,
          memory_line: mem_line
        )
      end
      # rubocop:enable Metrics/MethodLength

      def dashboard_config_hash
        {
          model: @agent.instance_variable_get(:@model),
          endpoint: ENV.fetch("OLLAMA_BASE_URL", "localhost (default)")
        }
      end

      def skills_summary_for_agent
        enabled = @agent.instance_variable_get(:@skills_enabled)
        paths   = @agent.instance_variable_get(:@skill_paths)
        parts = []
        parts << (enabled == false ? "off" : "on")
        parts << "paths: #{Array(paths).join(", ")}" if paths && !paths.empty?
        parts.join(" · ")
      end

      def scripts_placeholder
        []
      end

      def memory_summary_line
        mem = repl_memory
        return nil unless mem

        s = mem.summary
        "#{s[:short_term_entries]} short-term · #{s[:session_keys]} session keys"
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

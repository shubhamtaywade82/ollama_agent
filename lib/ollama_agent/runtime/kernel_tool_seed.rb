# frozen_string_literal: true

require "find"
require "open3"
require "pathname"
require "timeout"

require_relative "../env_config"
require_relative "../search_backend"
require_relative "../security/resource_guard"
require_relative "intent_translator"

module OllamaAgent
  module Runtime
    # Registers default phase-scoped tools on {OllamaAgent::ToolRuntime::ToolRegistry}.
    class KernelToolSeed
      MAX_READ_BYTES = 2_097_152
      MAX_LIST_FILES = 500

      def self.seed(tool_registry:, kernel_pipeline:)
        new(tool_registry: tool_registry, kernel_pipeline: kernel_pipeline).seed
      end

      def self.strip_meta_arguments(arguments)
        h = arguments.to_h.transform_keys { |k| k.respond_to?(:to_sym) ? k.to_sym : k }
        h.except(:manifest_id, :mode)
      end

      def initialize(tool_registry:, kernel_pipeline:)
        @tool_registry = tool_registry
        @kernel_pipeline = kernel_pipeline
        @root = kernel_pipeline.workspace_root
        @translator = IntentTranslator.new(workspace_root: @root)
        @planning = PlanningSandbox.new(@root)
      end

      def seed
        register_planning
        register_mutation_translated_tools
        register_verification_stubs
        register_integration_stubs
      end

      private

      def register_planning
        %i[read_file list_files search_files].each { |m| register_planning_tool(m) }
      end

      def register_planning_tool(method_name)
        @tool_registry.register(
          name: method_name.to_s,
          callable: ->(**args) { @planning.public_send(method_name, **args) },
          phases: %i[planning]
        )
      end

      def register_mutation_translated_tools
        %w[write_file edit_file apply_patch delete_file rename_file move_file].each do |name|
          register_mutation(name)
        end
      end

      def register_mutation(tool_name)
        @tool_registry.register(
          name: tool_name,
          callable: mutation_callable(tool_name),
          phases: %i[mutation]
        )
      end

      def mutation_callable(tool_name)
        pipeline = @kernel_pipeline
        translator = @translator
        lambda do |manifest_id:, mode: "normal", **arguments|
          args = KernelToolSeed.strip_meta_arguments(arguments)
          intent = translator.translate(tool_call: { name: tool_name, arguments: args })
          pipeline.execute(intent: intent, manifest_id: manifest_id.to_s, mode: mode.to_s)
        end
      end

      def register_verification_stubs
        msg = "KernelToolSeed: verification tools are stubs; use Agent or extend KernelToolSeed."
        stub = proc { raise NotImplementedError, msg }
        %w[run_tests run_lint run_command].each do |name|
          @tool_registry.register(name: name, callable: stub, phases: %i[verification])
        end
      end

      def register_integration_stubs
        msg = "KernelToolSeed: emit_event is a stub; use synthesis integration from the kernel."
        @tool_registry.register(
          name: "emit_event",
          callable: proc { raise NotImplementedError, msg },
          phases: %i[integration]
        )
      end

      # Read-only planning helpers scoped to +workspace_root+ (no Agent / TTY).
      class PlanningSandbox
        def initialize(root)
          @root = File.expand_path(root.to_s)
          @guard = Security::ResourceGuard.new(root: @root)
        end

        def read_file(path:, start_line: nil, end_line: nil, **_ignored)
          abs = File.expand_path(path.to_s, @root)
          return "path not allowed" unless @guard.allow?(abs)
          return "Error reading file: not a file" unless File.file?(abs)

          return read_line_range(abs, start_line, end_line) if start_line || end_line
          return "Error reading file: file too large (max #{MAX_READ_BYTES} bytes)" if File.size(abs) > MAX_READ_BYTES

          File.read(abs, encoding: Encoding::UTF_8)
        rescue Errno::ENOENT => e
          "Error reading file: #{e.message}"
        end

        def list_files(directory: ".", max_entries: 100, max_depth: nil, **_ignored)
          dir = directory.to_s.empty? ? "." : directory.to_s
          base = File.expand_path(dir, @root)
          return "path not allowed" unless @guard.allow?(base)
          return "Not a directory: #{dir}" unless File.directory?(base)

          cap = clamp_list_limit(max_entries)
          paths = collect_relative_paths(base, cap, max_depth: max_depth)
          return "(no files listed)" if paths.empty?

          body = paths.sort.join("\n")
          return body if paths.size < cap

          "#{body}\n(list truncated at #{cap} entries; pass max_entries or narrow directory)"
        end

        def search_files(pattern:, directory: ".", **_ignored)
          pat = pattern.to_s
          return "Error: search_files requires a non-empty pattern" if pat.strip.empty?

          dir = directory.to_s.empty? ? "." : directory.to_s
          abs = File.expand_path(dir, @root)
          return "path not allowed" unless @guard.allow?(abs)

          rg = SearchBackend.rg_executable
          grep = SearchBackend.grep_executable
          return SearchTextBackend.no_backends_message if rg.nil? && grep.nil?

          SearchTextBackend.search(ripgrep_bin: rg, grep_bin: grep, pattern: pat, target: abs)
        end

        private

        def read_line_range(abs, start_line, end_line)
          lines = File.readlines(abs, chomp: true)
          s = Integer(start_line || 1)
          e = end_line ? Integer(end_line) : lines.size
          slice = lines[(s - 1)..(e - 1)] || []
          slice.join("\n")
        rescue ArgumentError, TypeError
          "Error reading file: invalid start_line or end_line"
        rescue Errno::ENOENT => e
          "Error reading file: #{e.message}"
        end

        def clamp_list_limit(value)
          n = value.to_i
          n = 100 if n < 1
          [n, MAX_LIST_FILES].min
        end

        def collect_relative_paths(base, cap, max_depth:)
          paths = []
          base_pn = Pathname(base)
          catch(:kernel_seed_list_cap) do
            Find.find(base) { |path| visit_list_path(path, base_pn, paths, cap, max_depth) }
          end
          paths
        end

        def visit_list_path(path, base_pn, paths, cap, max_depth)
          if File.directory?(path) && File.basename(path) == ".git"
            Find.prune
          elsif File.file?(path)
            rel = Pathname(path).relative_path_from(base_pn)
            return if max_depth && rel.each_filename.count > max_depth

            paths << rel.to_s
            throw(:kernel_seed_list_cap) if paths.size >= cap
          end
        end
      end

      # ripgrep/grep text search (same backend selection as the Agent search tool).
      module SearchTextBackend
        module_function

        def no_backends_message
          <<~MSG.strip
            Error: ollama_agent: no text search backend available. Install ripgrep (`rg`) or GNU grep on PATH.
          MSG
        end

        def search(ripgrep_bin:, grep_bin:, pattern:, target:)
          if ripgrep_bin
            with_search_timeout { Open3.capture2(ripgrep_bin, "-n", "--", pattern, target) }
          else
            with_search_timeout { Open3.capture2(grep_bin, "-rn", "--", pattern, target) }
          end
        end

        def with_search_timeout(&)
          sec = search_timeout_seconds
          stdout, status = Timeout.timeout(sec, &)
          return stdout.to_s if status.success?

          "Error: ollama_agent: search command exited with status #{status.exitstatus}"
        rescue Timeout::Error
          timeout_message(sec)
        end

        def search_timeout_seconds
          EnvConfig.fetch_int(
            "OLLAMA_AGENT_SEARCH_TIMEOUT_SEC",
            120,
            strict: EnvConfig.strict_env?
          )
        end

        def timeout_message(seconds)
          tail = "(raise OLLAMA_AGENT_SEARCH_TIMEOUT_SEC for longer runs)."
          "Error: ollama_agent: search timed out after #{seconds}s #{tail}"
        end
      end
    end
  end
end

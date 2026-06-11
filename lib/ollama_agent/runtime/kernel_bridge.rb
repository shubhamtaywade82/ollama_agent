# frozen_string_literal: true

require "securerandom"

require_relative "intent_translator"
require_relative "kernel_feature"
require_relative "kernel_pipeline"
require_relative "permission_bridge"

module OllamaAgent
  module Runtime
    # Bridge object that preserves legacy behavior while exposing a kernel
    # integration hook behind a feature flag.
    # rubocop:disable Metrics/ClassLength -- agent dispatch + pipeline routing stay in one place
    class KernelBridge
      class << self
        # Tools routed through {KernelPipeline} (others stay on legacy guarded dispatch).
        def pipeline_tool_names
          default = "write_file,edit_file,apply_patch,delete_file,rename_file,move_file"
          parse_env_list("OLLAMA_AGENT_KERNEL_PIPELINE_TOOLS", default)
        end

        def parse_env_list(key, default)
          ENV.fetch(key, default).split(",").map(&:strip).reject(&:empty?)
        end
        private :parse_env_list
      end

      def initialize(session_manager:, toolbox:, hooks:, loop_detector:, memory_manager:,
                    config:, logger:, permissions:, policies:, pipeline: nil)
        @session_manager = session_manager
        @toolbox = toolbox
        @hooks = hooks
        @loop_detector = loop_detector
        @memory_manager = memory_manager
        @config = config
        @logger = logger
        @permissions = permissions
        @policies = policies
        @pipeline = pipeline
        @permission_bridge_memo = false
        @permission_bridge = nil
        @current_turn = 0
      end

      def append_tool_results(messages:, tool_calls:, turn: 0)
        @current_turn = turn
        return legacy_append(messages: messages, tool_calls: tool_calls) unless KernelFeature.enabled?

        emit_kernel_bridge_hook!(tool_calls)
        tool_calls.each { |tool_call| append_one_tool!(messages, tool_call) }
      end

      private

      def emit_kernel_bridge_hook!(tool_calls)
        @logger.info("kernel bridge enabled: routing tool execution through guarded path")
        @hooks.emit(
          :on_tool_runtime_kernel,
          {
            enabled: true,
            tool_call_count: tool_calls.length,
            pipeline_tools: self.class.pipeline_tool_names
          }
        )
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- mirrors SessionWiring tool loop
      def append_one_tool!(messages, tool_call)
        tc = coerce_tool_call(tool_call)
        name = tc.name
        args = tc.arguments || {}

        @hooks.emit(:on_tool_call, { name: name, args: args, turn: @current_turn })
        @loop_detector&.record!(name, args)

        result = dispatch_tool(name, args)

        @hooks.emit(:on_tool_result, { name: name, result: result.to_s, turn: @current_turn })
        @memory_manager&.record_tool_call(name, args, result)
        messages << @session_manager.tool_message(tc, result)
        @session_manager.save_message_to_session(messages.last)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      def coerce_tool_call(tool_call)
        return tool_call if tool_call.respond_to?(:name) && tool_call.respond_to?(:arguments)

        h = tool_call
        Struct.new(:name, :arguments, :id).new(
          (h["name"] || h[:name]).to_s,
          h["arguments"] || h[:arguments] || {},
          h["id"] || h[:id]
        )
      end

      def dispatch_tool(name, args)
        if self.class.pipeline_tool_names.include?(name.to_s)
          run_kernel_pipeline_tool(name, args)
        else
          guarded_tool_call(name, args)
        end
      end

      def guarded_tool_call(name, args)
        ctx = build_tool_context

        return "Permission denied: tool '#{name}' is not allowed under the current permission profile (#{@permissions.profile})." if @permissions && !@permissions.allowed?(name)

        if @policies
          rejection = @policies.evaluate(name, args, ctx)
          return rejection if rejection
        end

        @toolbox.execute(name, args, context: ctx)
      end

      def build_tool_context
        {
          root: @config.root,
          read_only: @config.runtime.read_only,
          memory_manager: @memory_manager,
          shell_call_count: 0
        }
      end

      def run_kernel_pipeline_tool(name, args)
        intent = IntentTranslator.new(workspace_root: @config.root).translate(
          tool_call: { "name" => name, "arguments" => args }
        )
        finish_kernel_pipeline_tool(name, args, intent)
      rescue ArgumentError => e
        "Kernel tool error: #{e.message}"
      end

      def finish_kernel_pipeline_tool(name, args, intent)
        if (rej = reject_pipeline_paths(name, intent))
          return rej
        end
        return "#{name} is disabled in read-only mode." if @config.runtime.read_only

        return "Mutation denied by kernel permission gate." unless pipeline_mutation_allowed?(name, intent)

        return "Cancelled by user" unless user_confirmed_mutation?(name, args, intent)

        manifest_id = SecureRandom.uuid
        mode = KernelFeature.shadow? ? "shadow" : "normal"
        outcome = pipeline.execute(intent: intent, manifest_id: manifest_id, mode: mode)
        format_pipeline_outcome(outcome)
      end

      def reject_pipeline_paths(name, intent)
        pipeline_paths_for_tool(name, intent).each do |path|
          return missing_tool_argument(name, "path") if blank_tool_value?(path)
          return disallowed_path_message(path) unless path_allowed?(path)
        end
        nil
      end

      def pipeline_paths_for_tool(name, intent)
        case name.to_s
        when "rename_file", "move_file"
          [intent[:from_path].to_s, intent[:to_path].to_s]
        else
          [intent[:path].to_s]
        end
      end

      def missing_tool_argument(name, arg)
        "Tool '#{name}' is missing required argument: #{arg}"
      end

      def blank_tool_value?(value)
        value.nil? || value.to_s.strip.empty?
      end

      def disallowed_path_message(path)
        "Path must stay under project root #{@config.root}: #{path}"
      end

      def path_allowed?(path)
        return false if blank_tool_value?(path)

        PathSandbox.allowed?(File.expand_path(@config.root), File.realpath(@config.root), path)
      rescue Errno::ENOENT, Errno::ELOOP, Errno::EACCES
        PathSandbox.allowed?(File.expand_path(@config.root), File.expand_path(@config.root), path)
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- tool + rename branching for bridge calls
      def pipeline_mutation_allowed?(name, intent)
        return true unless KernelFeature.enabled?

        bridge = permission_bridge
        return true unless bridge

        mode = KernelFeature.shadow? ? "shadow" : "normal"
        tool = name.to_s
        paths = pipeline_paths_for_tool(name, intent)

        if %w[rename_file move_file].include?(tool)
          return bridge.pipeline_allowed?(
            tool_name: tool,
            path: paths[0],
            mode: mode,
            read_only: @config.runtime.read_only,
            rename_to: paths[1],
            logger: @logger,
            root: @config.root
          )
        end

        paths.all? do |p|
          bridge.pipeline_allowed?(
            tool_name: tool,
            path: p,
            mode: mode,
            read_only: @config.runtime.read_only,
            rename_to: nil,
            logger: @logger,
            root: @config.root
          )
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # rubocop:disable Metrics/MethodLength -- lazy memo + compiler wiring
      def permission_bridge
        return @permission_bridge if @permission_bridge_memo

        @permission_bridge_memo = true
        path = File.join(@config.root, "config", "ollama_agent", "owners.yml")
        @permission_bridge =
          if File.exist?(path)
            PermissionBridge.new(
              permissions: @permissions,
              policies: @policies,
              ownership_index: OllamaAgent::Security::OwnershipCompiler.new.compile(path: path),
              workspace_root: @config.root
            )
          end
      end
      # rubocop:enable Metrics/MethodLength

      def user_confirmed_mutation?(name, args, intent)
        return true unless @config.runtime.confirm_patches

        prompt = UserPrompt.new(stdin: @config.session.stdin, stdout: @config.session.stdout)
        path = pipeline_paths_for_tool(name, intent).first.to_s
        confirm_for_pipeline_tool(name, args, intent, path, prompt)
      end

      def confirm_for_pipeline_tool(name, args, intent, path, prompt)
        case name.to_s
        when "write_file" then confirm_write_file_tool(args, path, prompt)
        when "edit_file" then confirm_edit_file_tool(args, path, intent, prompt)
        when "apply_patch" then confirm_apply_patch_tool(args, path, prompt)
        when "delete_file" then confirm_delete_file_tool(path, prompt)
        when "rename_file", "move_file" then confirm_rename_file_tool(intent, prompt)
        else true
        end
      end

      def confirm_delete_file_tool(path, prompt)
        prompt.confirm_write_file(path, "DELETE #{path}")
      end

      def confirm_rename_file_tool(intent, prompt)
        from = intent[:from_path].to_s
        to = intent[:to_path].to_s
        prompt.confirm_write_file(from, "RENAME #{from} -> #{to}")
      end

      def confirm_write_file_tool(args, path, prompt)
        args = args.to_h
        content = args["content"] || args[:content]
        prompt.confirm_write_file(path, content.to_s[0, 2000])
      end

      def confirm_edit_file_tool(args, path, intent, prompt)
        args = args.to_h
        diff = args["diff"] || args[:diff]
        return prompt.confirm_patch(path, diff.to_s) if diff

        preview = intent[:edits].map { |e| "#{e[:search]} => #{e[:replace]}" }.join("\n")
        prompt.confirm_write_file(path, preview[0, 2000])
      end

      def confirm_apply_patch_tool(args, path, prompt)
        args = args.to_h
        patch = args["patch"] || args[:patch]
        diff = args["diff"] || args[:diff]
        prompt.confirm_patch(path, (patch || diff).to_s)
      end

      def format_pipeline_outcome(out)
        case out[:result]
        when :ok
          "Written via kernel (manifest_id=#{out[:manifest_id]}, state=#{out[:state]})"
        when :precondition_failed, :unknown_intent_kind
          "Kernel write failed: #{out[:error]}"
        else
          msg = out[:error] || "state=#{out[:state]}"
          "Kernel write failed: #{msg}"
        end
      end

      def pipeline
        @pipeline ||= KernelPipeline.build_for_workspace(workspace_root: @config.root)
      end

      def legacy_append(messages:, tool_calls:)
        @session_manager.dispatch_tool_results(messages, tool_calls)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
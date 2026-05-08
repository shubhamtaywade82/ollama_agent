# frozen_string_literal: true

require "digest"
require "securerandom"

require_relative "cas_guard"
require_relative "kernel_feature"
require_relative "kernel_pipeline"

module OllamaAgent
  module Runtime
    # Bridge object that preserves legacy behavior while exposing a kernel
    # integration hook behind a feature flag.
    # rubocop:disable Metrics/ClassLength -- agent dispatch + pipeline routing stay in one place
    class KernelBridge
      class << self
        # Tools routed through {KernelPipeline} (others stay on legacy guarded dispatch).
        def pipeline_tool_names
          parse_env_list("OLLAMA_AGENT_KERNEL_PIPELINE_TOOLS", "write_file")
        end

        def parse_env_list(key, default)
          ENV.fetch(key, default).split(",").map(&:strip).reject(&:empty?)
        end
        private :parse_env_list
      end

      def initialize(agent, pipeline: nil)
        @agent = agent
        @pipeline = pipeline
      end

      def append_tool_results(messages:, tool_calls:)
        return legacy_append(messages: messages, tool_calls: tool_calls) unless KernelFeature.enabled?

        emit_kernel_bridge_hook!(tool_calls)
        tool_calls.each { |tool_call| append_one_tool!(messages, tool_call) }
      end

      private

      def emit_kernel_bridge_hook!(tool_calls)
        @agent.logger.info("kernel bridge enabled: routing tool execution through guarded path")
        @agent.hooks.emit(
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
        turn = @agent.instance_variable_get(:@current_turn) || 0

        @agent.hooks.emit(:on_tool_call, { name: name, args: args, turn: turn })
        @agent.instance_variable_get(:@loop_detector)&.record!(name, args)

        result = dispatch_tool(name, args)

        @agent.hooks.emit(:on_tool_result, { name: name, result: result.to_s, turn: turn })
        @agent.instance_variable_get(:@memory_manager)&.record_tool_call(name, args, result)
        messages << @agent.send(:tool_message, tc, result)
        @agent.send(:save_message_to_session, messages.last)
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
          run_kernel_write_file(args)
        else
          @agent.send(:platform_guarded_tool_call, name, args)
        end
      end

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/AbcSize
      def run_kernel_write_file(args)
        path = args["path"] || args[:path]
        content = args["content"] || args[:content]
        return @agent.send(:missing_tool_argument, "write_file", "path") if @agent.send(:blank_tool_value?, path)
        return @agent.send(:missing_tool_argument, "write_file", "content") if content.nil?

        return @agent.send(:disallowed_path_message, path) unless @agent.send(:path_allowed?, path)
        return "write_file is disabled in read-only mode." if @agent.read_only

        if @agent.instance_variable_get(:@confirm_patches) &&
           !@agent.send(:user_prompt).confirm_write_file(path, content.to_s[0, 2000])
          return "Cancelled by user"
        end

        manifest_id = SecureRandom.uuid
        intent = {
          kind: "atomic_write",
          path: path.to_s,
          content: content.to_s,
          expected_pre_hash: expected_pre_hash_for(path),
          post_conditions: [],
          scopes: []
        }
        outcome = pipeline.execute(intent: intent, manifest_id: manifest_id, mode: "normal")
        format_pipeline_outcome(outcome)
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/AbcSize

      def expected_pre_hash_for(path)
        abs = @agent.send(:resolve_path, path)
        return CASGuard::NEW_FILE_SENTINEL unless File.file?(abs)

        Digest::SHA256.hexdigest(File.binread(abs).b)
      end

      def format_pipeline_outcome(out)
        if out[:result] == :ok
          "Written via kernel (manifest_id=#{out[:manifest_id]}, state=#{out[:state]})"
        else
          msg = out[:error] || "state=#{out[:state]}"
          "Kernel write failed: #{msg}"
        end
      end

      def pipeline
        @pipeline ||= KernelPipeline.build_for_workspace(workspace_root: @agent.root)
      end

      # TODO(kernel): Replace with a public Agent API (e.g. #dispatch_tool_results) once the
      # kernel owns tool dispatch; remove send-to-private when cutover is complete.
      def legacy_append(messages:, tool_calls:)
        @agent.send(:append_tool_results, messages, tool_calls)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

# frozen_string_literal: true

require "fileutils"

require "spec_helper"

# rubocop:disable RSpec/MultipleMemoizedHelpers -- agent tmp workspace + doubles
RSpec.describe OllamaAgent::Runtime::KernelBridge do
  def minimal_owners_yaml
    <<~YAML
      rules:
        - prefix: lib
          owner: libraries
          mutable_in_modes: [normal, replay, validation, dry_run]
          criticality: routine
          children: []
    YAML
  end

  def fake_validator
    instance_double(OllamaAgent::Runtime::IsolatedValidator).tap do |v|
      ok = { status: :ok, exit_code: 0, stdout: "", stderr: "", image_digest: nil }
      allow(v).to receive(:run).and_return(ok)
    end
  end

  let(:hooks) { instance_double(OllamaAgent::Streaming::Hooks, emit: nil) }
  let(:logger) { instance_double(Logger, info: nil) }
  let(:agent_workspace) { Dir.mktmpdir("kernel-bridge-agent") }
  let(:agent) do
    instance_double(
      OllamaAgent::Agent,
      hooks: hooks,
      logger: logger,
      root: agent_workspace,
      read_only: false,
      current_turn: 2
    )
  end

  after do
    FileUtils.rm_rf(agent_workspace) if agent_workspace && File.directory?(agent_workspace)
  end

  around do |example|
    original_value = ENV.fetch("OLLAMA_AGENT_KERNEL", nil)
    example.run
    ENV["OLLAMA_AGENT_KERNEL"] = original_value
  end

  describe "#append_tool_results" do
    let(:messages) { [{ role: "user", content: "hi" }] }
    let(:tool_calls) { [{ "name" => "read_file", "arguments" => { "path" => "README.md" } }] }

    context "when kernel flag is disabled" do
      before { allow(agent).to receive(:send) }

      it "uses legacy append behavior without emitting kernel event" do
        ENV["OLLAMA_AGENT_KERNEL"] = "false"
        bridge = described_class.new(agent)

        bridge.append_tool_results(messages: messages, tool_calls: tool_calls)

        expect(agent).to have_received(:send).with(:append_tool_results, messages, tool_calls)
        expect(hooks).not_to have_received(:emit)
      end

      it "does not create kernel SQLite files (no saga persistence)" do
        Dir.mktmpdir("kernel-bridge-off") do |root|
          ENV["OLLAMA_AGENT_KERNEL"] = "false"
          local_agent = instance_double(
            OllamaAgent::Agent,
            hooks: hooks,
            logger: logger,
            root: root,
            read_only: false
          )
          allow(local_agent).to receive(:send).with(:append_tool_results, anything, anything)
          bridge = described_class.new(local_agent)
          write_call = [{
            "name" => "write_file",
            "arguments" => { "path" => "lib/x.rb", "content" => "1" }
          }]

          bridge.append_tool_results(messages: messages, tool_calls: write_call)

          kernel_dir = File.join(root, ".ollama_agent", "kernel")
          expect(Dir.exist?(kernel_dir)).to be(false)
        end
      end
    end

    context "when kernel flag is enabled" do
      before do
        iv = { :@current_turn => 2, :@confirm_patches => false, :@loop_detector => nil, :@memory_manager => nil }
        allow(agent).to receive(:instance_variable_get) { |k| iv[k] }
        allow(agent).to receive(:send) do |method, *args|
          case method
          when :platform_guarded_tool_call
            "read-ok"
          when :tool_message
            tc = args[0]
            { role: "tool", name: tc.name, content: args[1].to_s }
          when :save_message_to_session
            nil
          when :blank_tool_value?
            args.first.to_s.strip.empty?
          end
        end
      end

      it "emits kernel telemetry and routes non-pipeline tools through the guarded path" do
        ENV["OLLAMA_AGENT_KERNEL"] = "true"
        bridge = described_class.new(agent)

        bridge.append_tool_results(messages: messages, tool_calls: tool_calls)

        expect(hooks).to have_received(:emit).with(
          :on_tool_runtime_kernel,
          hash_including(enabled: true, tool_call_count: 1, pipeline_tools: kind_of(Array))
        )
        expect(agent).not_to have_received(:send).with(:append_tool_results, anything, anything)
        expect(agent).to have_received(:send).with(:platform_guarded_tool_call, "read_file", kind_of(Hash))
      end

      # rubocop:disable RSpec/ExampleLength -- explicit pipeline + Agent send stubs
      it "routes write_file through the kernel pipeline" do
        ENV["OLLAMA_AGENT_KERNEL"] = "true"
        pl_out = { result: :ok, state: "committed", manifest_id: "m1" }
        pipeline = instance_double(OllamaAgent::Runtime::KernelPipeline, execute: pl_out)
        bridge = described_class.new(agent, pipeline: pipeline)
        calls = [{ "name" => "write_file", "arguments" => { "path" => "lib/x.rb", "content" => "1" } }]

        allow(agent).to receive(:send) do |method, *args|
          case method
          when :missing_tool_argument, :disallowed_path_message
            "err"
          when :blank_tool_value?
            args.first.to_s.strip.empty?
          when :path_allowed?
            true
          when :user_prompt
            instance_double(OllamaAgent::UserPrompt, confirm_write_file: true)
          when :resolve_path
            File.expand_path(args[0].to_s, agent.root)
          when :tool_message
            tc = args[0]
            { role: "tool", name: tc.name, content: args[1].to_s }
          when :save_message_to_session
            nil
          when :platform_guarded_tool_call
            raise "legacy guarded path should not run for write_file"
          end
        end

        bridge.append_tool_results(messages: messages, tool_calls: calls)

        expect(pipeline).to have_received(:execute).with(
          hash_including(
            intent: hash_including(kind: "atomic_write", path: "lib/x.rb", content: "1"),
            manifest_id: kind_of(String),
            mode: "normal"
          )
        )
      end

      it "routes edit_file with search/replace through the kernel pipeline" do
        ENV["OLLAMA_AGENT_KERNEL"] = "true"
        pl_out = { result: :ok, state: "committed", manifest_id: "m2" }
        pipeline = instance_double(OllamaAgent::Runtime::KernelPipeline, execute: pl_out)
        bridge = described_class.new(agent, pipeline: pipeline)
        calls = [{
          "name" => "edit_file",
          "arguments" => { "path" => "lib/e.rb", "search" => "a", "replace" => "b" }
        }]

        FileUtils.mkdir_p(File.join(agent_workspace, "lib"))
        File.write(File.join(agent_workspace, "lib", "e.rb"), "a")

        allow(agent).to receive(:send) do |method, *args|
          case method
          when :missing_tool_argument, :disallowed_path_message
            "err"
          when :blank_tool_value?
            args.first.to_s.strip.empty?
          when :path_allowed?
            true
          when :user_prompt
            instance_double(OllamaAgent::UserPrompt, confirm_write_file: true, confirm_patch: true)
          when :resolve_path
            File.expand_path(args[0].to_s, agent.root)
          when :tool_message
            tc = args[0]
            { role: "tool", name: tc.name, content: args[1].to_s }
          when :save_message_to_session
            nil
          when :platform_guarded_tool_call
            raise "legacy guarded path should not run for edit_file"
          end
        end

        bridge.append_tool_results(messages: messages, tool_calls: calls)

        expect(pipeline).to have_received(:execute).with(
          hash_including(
            intent: hash_including(kind: "edit_file", path: "lib/e.rb"),
            manifest_id: kind_of(String),
            mode: "normal"
          )
        )
      end

      it "routes apply_patch through the kernel pipeline" do
        ENV["OLLAMA_AGENT_KERNEL"] = "true"
        pl_out = { result: :ok, state: "committed", manifest_id: "m3" }
        pipeline = instance_double(OllamaAgent::Runtime::KernelPipeline, execute: pl_out)
        bridge = described_class.new(agent, pipeline: pipeline)
        diff = <<~DIFF
          diff --git a/lib/p.rb b/lib/p.rb
          --- a/lib/p.rb
          +++ b/lib/p.rb
          @@ -1,1 +1,1 @@
          -x
          +y
        DIFF
        calls = [{ "name" => "apply_patch", "arguments" => { "patch" => diff } }]

        FileUtils.mkdir_p(File.join(agent_workspace, "lib"))
        File.write(File.join(agent_workspace, "lib", "p.rb"), "x")

        allow(agent).to receive(:send) do |method, *args|
          case method
          when :missing_tool_argument, :disallowed_path_message
            "err"
          when :blank_tool_value?
            args.first.to_s.strip.empty?
          when :path_allowed?
            true
          when :user_prompt
            instance_double(OllamaAgent::UserPrompt, confirm_write_file: true, confirm_patch: true)
          when :resolve_path
            File.expand_path(args[0].to_s, agent.root)
          when :tool_message
            tc = args[0]
            { role: "tool", name: tc.name, content: args[1].to_s }
          when :save_message_to_session
            nil
          when :platform_guarded_tool_call
            raise "legacy guarded path should not run for apply_patch"
          end
        end

        bridge.append_tool_results(messages: messages, tool_calls: calls)

        expect(pipeline).to have_received(:execute).with(
          hash_including(
            intent: hash_including(kind: "apply_patch", path: "lib/p.rb"),
            manifest_id: kind_of(String),
            mode: "normal"
          )
        )
      end

      it "persists a saga row when write_file runs through a real pipeline" do
        Dir.mktmpdir("kernel-bridge-on") do |root|
          ENV["OLLAMA_AGENT_KERNEL"] = "true"
          FileUtils.mkdir_p(File.join(root, "lib"))
          tick = [0]
          clock = proc { tick[0] += 1 }
          index = OllamaAgent::Security::OwnershipCompiler.new.compile(yaml_string: minimal_owners_yaml)
          pipeline = OllamaAgent::Runtime::KernelPipeline.build_for_workspace(
            workspace_root: root,
            ownership_index: index,
            clock_epoch_provider: clock,
            isolated_validator: fake_validator
          )
          local_agent = instance_double(
            OllamaAgent::Agent,
            hooks: hooks,
            logger: logger,
            root: root,
            read_only: false
          )
          iv = { :@current_turn => 0, :@confirm_patches => false, :@loop_detector => nil, :@memory_manager => nil }
          allow(local_agent).to receive(:instance_variable_get) { |k| iv[k] }
          allow(local_agent).to receive(:send) do |method, *args|
            case method
            when :missing_tool_argument, :disallowed_path_message
              "err"
            when :blank_tool_value?
              args.first.to_s.strip.empty?
            when :path_allowed?
              true
            when :user_prompt
              instance_double(OllamaAgent::UserPrompt, confirm_write_file: true)
            when :resolve_path
              File.expand_path(args[0].to_s, root)
            when :tool_message
              tc = args[0]
              { role: "tool", name: tc.name, content: args[1].to_s }
            when :save_message_to_session
              nil
            when :platform_guarded_tool_call
              raise "legacy guarded path should not run for write_file"
            end
          end

          bridge = described_class.new(local_agent, pipeline: pipeline)
          manifest_id = nil
          allow(pipeline).to receive(:execute).and_wrap_original do |m, **kwargs|
            manifest_id = kwargs[:manifest_id]
            m.call(**kwargs)
          end
          calls = [{ "name" => "write_file", "arguments" => { "path" => "lib/x.rb", "content" => "ok" } }]
          bridge.append_tool_results(messages: messages, tool_calls: calls)

          db = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root).runtime
          n = db.get_first_value("SELECT COUNT(*) FROM sagas WHERE manifest_id = ?", [manifest_id]).to_i
          expect(n).to eq(1)
          expect(File.read(File.join(root, "lib", "x.rb"))).to eq("ok")
        end
      end
      # rubocop:enable RSpec/ExampleLength
    end
  end

  describe ".pipeline_tool_names" do
    it "includes delete, rename, and move when env is unset" do
      previous = ENV.fetch("OLLAMA_AGENT_KERNEL_PIPELINE_TOOLS", nil)
      ENV.delete("OLLAMA_AGENT_KERNEL_PIPELINE_TOOLS")
      expect(described_class.pipeline_tool_names).to eq(
        %w[write_file edit_file apply_patch delete_file rename_file move_file]
      )
    ensure
      if previous
        ENV["OLLAMA_AGENT_KERNEL_PIPELINE_TOOLS"] = previous
      else
        ENV.delete("OLLAMA_AGENT_KERNEL_PIPELINE_TOOLS")
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers

# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::KernelToolSeed do
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

  def build_pipeline(root)
    tick = [0]
    clock = proc { tick[0] += 1 }
    index = OllamaAgent::Security::OwnershipCompiler.new.compile(yaml_string: minimal_owners_yaml)
    OllamaAgent::Runtime::KernelPipeline.build_for_workspace(
      workspace_root: root,
      ownership_index: index,
      clock_epoch_provider: clock,
      isolated_validator: fake_validator
    )
  end

  it "exposes planning read tools only in the planning phase" do
    Dir.mktmpdir("kernel-tool-seed-plan") do |root|
      File.write(File.join(root, "note.txt"), "hello-seed")
      registry = OllamaAgent::ToolRuntime::ToolRegistry.new
      pipeline = build_pipeline(root)
      OllamaAgent.seed_kernel_tools(registry: registry, pipeline: pipeline)

      expect(registry.invoke(name: "read_file", phase: :planning, path: "note.txt")).to eq("hello-seed")
      expect(registry.invoke(name: "read_file", phase: :mutation, path: "note.txt")).to eq(:tool_not_available_in_phase)
    end
  end

  it "routes mutation delete_file through the kernel pipeline" do
    Dir.mktmpdir("kernel-tool-seed-mut") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib", "gone.rb"), "# x")

      registry = OllamaAgent::ToolRuntime::ToolRegistry.new
      pipeline = build_pipeline(root)
      allow(pipeline).to receive(:execute).and_return(
        { result: :ok, state: "committed", manifest_id: "m-del" }
      )
      OllamaAgent.seed_kernel_tools(registry: registry, pipeline: pipeline)

      registry.invoke(
        name: "delete_file",
        phase: :mutation,
        manifest_id: "m-del",
        path: "lib/gone.rb"
      )

      expect(pipeline).to have_received(:execute).with(
        hash_including(
          manifest_id: "m-del",
          intent: hash_including(kind: "delete_file", path: "lib/gone.rb")
        )
      )
    end
  end
end

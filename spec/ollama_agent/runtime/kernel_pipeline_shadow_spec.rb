# frozen_string_literal: true

require "spec_helper"

module KernelPipelineShadowHookSink
  module_function

  def build
    log = []
    mx = Mutex.new
    r = Object.new
    r.define_singleton_method(:emit) { |ev, pl| mx.synchronize { log << [ev, pl.dup] } }
    [r, log]
  end
end

# rubocop:disable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
RSpec.describe OllamaAgent::Runtime::KernelPipeline, "shadow execution mode" do
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

  def build_pipeline(root, hooks: nil)
    tick = [0]
    clock = proc { tick[0] += 1 }
    index = OllamaAgent::Security::OwnershipCompiler.new.compile(yaml_string: minimal_owners_yaml)
    OllamaAgent::Runtime::KernelPipeline.build_for_workspace(
      workspace_root: root,
      ownership_index: index,
      clock_epoch_provider: clock,
      isolated_validator: fake_validator,
      hooks: hooks
    )
  end

  it "runs saga to committed, records WAL + shadow compensation, leaves bytes unchanged, emits hooks" do
    Dir.mktmpdir("kernel-shadow") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "unchanged.txt")
      File.write(path, "before")

      hooks, log = KernelPipelineShadowHookSink.build
      pipeline = build_pipeline(root, hooks: hooks)
      pre = Digest::SHA256.hexdigest(File.binread(path).b)

      intent = {
        kind: "atomic_write",
        path: "lib/unchanged.txt",
        content: "after",
        expected_pre_hash: pre,
        post_conditions: [],
        scopes: []
      }
      out = pipeline.execute(intent: intent, manifest_id: "manifest-shadow-1", mode: "shadow")
      expect(out[:result]).to eq(:ok)
      expect(out[:state]).to eq("committed")
      expect(File.read(path)).to eq("before")

      expect(log.map(&:first)).to include(:on_saga_start, :on_kernel_pipeline_complete)

      db = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root).runtime
      row = db.get_first_row("SELECT op FROM compensations WHERE manifest_id = ?", ["manifest-shadow-1"])
      expect(row["op"]).to eq("shadow")

      reg = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
      store = OllamaAgent::Runtime::EventStore.new(reg.event_store)
      n = 0
      store.each_mutation_globally { n += 1 }
      expect(n).to be >= 1
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat, RSpec/DescribeMethod

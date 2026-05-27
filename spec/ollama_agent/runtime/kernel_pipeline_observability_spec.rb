# frozen_string_literal: true

require "spec_helper"

module KernelPipelineObservabilityHarness
  module_function

  def hook_sink
    log = []
    mx = Mutex.new
    receiver = Object.new
    receiver.define_singleton_method(:emit) do |event, payload|
      mx.synchronize { log << [event, payload.dup] }
    end
    [receiver, log]
  end
end

# rubocop:disable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
RSpec.describe OllamaAgent::Runtime::KernelPipeline, "observability hooks" do
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

  def fake_validator(verify_ok: true)
    instance_double(OllamaAgent::Runtime::IsolatedValidator).tap do |v|
      payload = { status: :ok, exit_code: verify_ok ? 0 : 1, stdout: "", stderr: "", image_digest: nil }
      allow(v).to receive(:run).and_return(payload)
    end
  end

  def build_pipeline(root, hooks:, validator: nil)
    tick = [0]
    clock = proc { tick[0] += 1 }
    index = OllamaAgent::Security::OwnershipCompiler.new.compile(yaml_string: minimal_owners_yaml)
    OllamaAgent::Runtime::KernelPipeline.build_for_workspace(
      workspace_root: root,
      ownership_index: index,
      clock_epoch_provider: clock,
      isolated_validator: validator || fake_validator,
      hooks: hooks
    )
  end

  def happy_intent
    {
      kind: "atomic_write",
      path: "lib/new.txt",
      content: "hello",
      expected_pre_hash: OllamaAgent::Runtime::CASGuard::NEW_FILE_SENTINEL,
      post_conditions: [],
      scopes: []
    }
  end

  it "emits saga + completion events in order on a committed atomic_write" do
    Dir.mktmpdir("kernel-obs-happy") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      hooks, log = KernelPipelineObservabilityHarness.hook_sink
      pipeline = build_pipeline(root, hooks: hooks)

      out = pipeline.execute(intent: happy_intent, manifest_id: "manifest-obs-ok", mode: "normal")
      expect(out[:result]).to eq(:ok)

      expect(log.map(&:first)).to eq(
        %i[
          on_saga_start
          on_saga_advance
          on_saga_advance
          on_saga_advance
          on_saga_advance
          on_saga_advance
          on_kernel_pipeline_complete
        ]
      )

      expect(log[0][1][:manifest_id]).to eq("manifest-obs-ok")
      expect(log[0][1][:kind]).to eq("atomic_write")
      expected_states = %i[locked mutations_applied verified integration_queued committed]
      expect(log[1..5].map { |(_e, p)| p[:state] }).to eq(expected_states)
      expect(log.last[1][:result]).to eq(:ok)
    end
  end

  it "emits compensate then completion when post-conditions fail" do
    Dir.mktmpdir("kernel-obs-comp") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      hooks, log = KernelPipelineObservabilityHarness.hook_sink
      pipeline = build_pipeline(root, hooks: hooks, validator: fake_validator(verify_ok: false))

      intent = happy_intent.merge(
        path: "lib/x.txt",
        post_conditions: [{ name: "chk", command: %w[/bin/true], expect_exit: 0 }]
      )
      out = pipeline.execute(intent: intent, manifest_id: "manifest-obs-comp", mode: "normal")
      expect(out[:result]).to eq(:error)

      expect(log.map(&:first)).to eq(
        %i[on_saga_start on_saga_advance on_saga_advance on_saga_compensate on_kernel_pipeline_complete]
      )
      expect(log[3][1][:reason]).to eq("post_condition failed")
      expect(log.last[1][:result]).to eq(:error)
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat, RSpec/DescribeMethod

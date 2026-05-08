# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::KernelPipeline do
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

  def failing_validator
    instance_double(OllamaAgent::Runtime::IsolatedValidator).tap do |v|
      bad = { status: :ok, exit_code: 1, stdout: "", stderr: "no", image_digest: nil }
      allow(v).to receive(:run).and_return(bad)
    end
  end

  def build_pipeline(root, validator)
    tick = [0]
    clock = proc { tick[0] += 1 }
    index = OllamaAgent::Security::OwnershipCompiler.new.compile(yaml_string: minimal_owners_yaml)
    described_class.build_for_workspace(
      workspace_root: root,
      ownership_index: index,
      clock_epoch_provider: clock,
      isolated_validator: validator
    )
  end

  it "commits after a successful atomic write" do
    Dir.mktmpdir("kernel-pipeline-happy") do |root|
      pipeline = build_pipeline(root, fake_validator)
      mid = "manifest-happy-1"
      intent = {
        kind: "atomic_write",
        path: "lib/out.txt",
        content: "hello",
        expected_pre_hash: OllamaAgent::Runtime::CASGuard::NEW_FILE_SENTINEL,
        post_conditions: [{ name: "noop", command: ["true"], expect_exit: 0 }],
        scopes: []
      }
      out = pipeline.execute(intent: intent, manifest_id: mid, mode: "normal")
      expect(out[:result]).to eq(:ok)
      expect(out[:state]).to eq("committed")
      expect(File.read(File.join(root, "lib", "out.txt"))).to eq("hello")

      db = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root).runtime
      expect(db.get_first_value("SELECT COUNT(*) FROM sagas WHERE manifest_id = ?", [mid]).to_i).to eq(1)
    end
  end

  it "compensates and restores prior bytes when post-conditions fail" do
    Dir.mktmpdir("kernel-pipeline-comp") do |root|
      path = File.join(root, "lib", "x.txt")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "before")

      mid = "manifest-comp-1"
      intent_fail = {
        kind: "atomic_write",
        path: "lib/x.txt",
        content: "after",
        expected_pre_hash: Digest::SHA256.hexdigest(File.binread(path).b),
        post_conditions: [{ name: "bad", command: ["true"], expect_exit: 0 }],
        scopes: []
      }
      pipeline = build_pipeline(root, failing_validator)
      out = pipeline.execute(intent: intent_fail, manifest_id: mid, mode: "normal")
      expect(out[:result]).to eq(:error)
      expect(out[:state]).to eq("compensated")
      expect(File.read(path)).to eq("before")
    end
  end
end

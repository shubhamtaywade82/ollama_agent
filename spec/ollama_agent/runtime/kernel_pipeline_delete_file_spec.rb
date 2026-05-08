# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
RSpec.describe OllamaAgent::Runtime::KernelPipeline, "delete_file intent" do
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

  def build_pipeline(root, validator: nil)
    tick = [0]
    clock = proc { tick[0] += 1 }
    index = OllamaAgent::Security::OwnershipCompiler.new.compile(yaml_string: minimal_owners_yaml)
    OllamaAgent::Runtime::KernelPipeline.build_for_workspace(
      workspace_root: root,
      ownership_index: index,
      clock_epoch_provider: clock,
      isolated_validator: validator || fake_validator
    )
  end

  it "commits after deleting an existing file" do
    Dir.mktmpdir("kernel-del-happy") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "gone.txt")
      File.write(path, "payload")
      pre = Digest::SHA256.hexdigest(File.binread(path).b)

      pipeline = build_pipeline(root)
      intent = {
        kind: "delete_file",
        path: "lib/gone.txt",
        expected_pre_hash: pre,
        post_conditions: [],
        scopes: []
      }
      out = pipeline.execute(intent: intent, manifest_id: "manifest-del-ok", mode: "normal")
      expect(out[:result]).to eq(:ok)
      expect(out[:state]).to eq("committed")
      expect(File.exist?(path)).to be(false)
    end
  end

  it "returns precondition_failed when expected_pre_hash is stale" do
    Dir.mktmpdir("kernel-del-stale") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "stale.txt")
      File.write(path, "v1")

      pipeline = build_pipeline(root)
      intent = {
        kind: "delete_file",
        path: "lib/stale.txt",
        expected_pre_hash: "0" * 64,
        post_conditions: [],
        scopes: []
      }
      out = pipeline.execute(intent: intent, manifest_id: "manifest-del-stale", mode: "normal")
      expect(out[:result]).to eq(:precondition_failed)
      expect(out[:error]).to eq("expected_pre_hash mismatch")
      expect(File.read(path)).to eq("v1")
    end
  end

  it "restores deleted bytes from the blob store when post-conditions fail" do
    Dir.mktmpdir("kernel-del-comp") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "restore_me.txt")
      File.write(path, "original-bytes")

      pipeline = build_pipeline(root, validator: fake_validator(verify_ok: false))
      pre = Digest::SHA256.hexdigest(File.binread(path).b)
      intent = {
        kind: "delete_file",
        path: "lib/restore_me.txt",
        expected_pre_hash: pre,
        post_conditions: [{ name: "must_fail", command: %w[/bin/true], expect_exit: 0 }],
        scopes: []
      }
      out = pipeline.execute(intent: intent, manifest_id: "manifest-del-comp", mode: "normal")
      expect(out[:result]).to eq(:error)
      expect(File.file?(path)).to be(true)
      expect(File.binread(path).b).to eq("original-bytes".b)
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat, RSpec/DescribeMethod

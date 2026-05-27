# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/SpecFilePathFormat, RSpec/DescribeMethod -- grouped #execute scenarios by intent kind
RSpec.describe OllamaAgent::Runtime::KernelPipeline, "apply_patch intent" do
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

  let(:unified_diff) do
    <<~DIFF
      diff --git a/lib/patched.txt b/lib/patched.txt
      --- a/lib/patched.txt
      +++ b/lib/patched.txt
      @@ -1,3 +1,3 @@
       alpha
      -beta
      +BETA
       gamma
    DIFF
  end

  it "commits after applying a unified diff" do
    Dir.mktmpdir("kernel-patch-happy") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "patched.txt")
      File.write(path, "alpha\nbeta\ngamma\n")

      pre = Digest::SHA256.hexdigest(File.binread(path).b)
      pipeline = build_pipeline(root)
      mid = "manifest-patch-happy"
      intent = {
        kind: "apply_patch",
        path: "lib/patched.txt",
        patch: unified_diff,
        expected_pre_hash: pre,
        post_conditions: [],
        scopes: []
      }
      out = pipeline.execute(intent: intent, manifest_id: mid, mode: "normal")
      expect(out[:result]).to eq(:ok)
      expect(out[:state]).to eq("committed")
      expect(File.read(path)).to eq("alpha\nBETA\ngamma\n")
    end
  end

  it "returns precondition_failed when patch does not apply to current content" do
    Dir.mktmpdir("kernel-patch-bad") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "patched.txt")
      File.write(path, "wrong\ncontent\nhere\n")

      pre = Digest::SHA256.hexdigest(File.binread(path).b)
      pipeline = build_pipeline(root)
      intent = {
        kind: "apply_patch",
        path: "lib/patched.txt",
        patch: unified_diff,
        expected_pre_hash: pre,
        post_conditions: [],
        scopes: []
      }
      out = pipeline.execute(intent: intent, manifest_id: "m-bad-patch", mode: "normal")
      expect(out[:result]).to eq(:precondition_failed)
      expect(out[:error]).to eq("patch did not apply cleanly")
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat, RSpec/DescribeMethod

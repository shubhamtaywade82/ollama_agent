# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/SpecFilePathFormat, RSpec/DescribeMethod -- grouped #execute scenarios by intent kind
RSpec.describe OllamaAgent::Runtime::KernelPipeline, "edit_file intent" do
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

  it "commits after sequential first-occurrence edits" do
    Dir.mktmpdir("kernel-edit-happy") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "f.txt")
      File.write(path, "aaa foo bbb foo ccc")

      pre = Digest::SHA256.hexdigest(File.binread(path).b)
      pipeline = build_pipeline(root)
      mid = "manifest-edit-happy"
      intent = {
        kind: "edit_file",
        path: "lib/f.txt",
        expected_pre_hash: pre,
        edits: [
          { search: "foo", replace: "BAR" },
          { search: "BAR", replace: "baz" }
        ],
        post_conditions: [],
        scopes: []
      }
      out = pipeline.execute(intent: intent, manifest_id: mid, mode: "normal")
      expect(out[:result]).to eq(:ok)
      expect(out[:state]).to eq("committed")
      expect(File.read(path)).to eq("aaa baz bbb foo ccc")
    end
  end

  it "returns precondition_failed when a search string is missing" do
    Dir.mktmpdir("kernel-edit-miss") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "g.txt")
      File.write(path, "hello")

      pre = Digest::SHA256.hexdigest(File.binread(path).b)
      pipeline = build_pipeline(root)
      intent = {
        kind: "edit_file",
        path: "lib/g.txt",
        expected_pre_hash: pre,
        edits: [{ search: "nope", replace: "x" }],
        post_conditions: [],
        scopes: []
      }
      out = pipeline.execute(intent: intent, manifest_id: "m-miss", mode: "normal")
      expect(out[:result]).to eq(:precondition_failed)
      expect(out[:error]).to eq("search not found")
      expect(File.read(path)).to eq("hello")
    end
  end

  it "returns precondition_failed when expected_pre_hash does not match disk" do
    Dir.mktmpdir("kernel-edit-hash") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "h.txt")
      File.write(path, "v1")

      pipeline = build_pipeline(root)
      intent = {
        kind: "edit_file",
        path: "lib/h.txt",
        expected_pre_hash: "0" * 64,
        edits: [{ search: "v1", replace: "v2" }],
        post_conditions: [],
        scopes: []
      }
      out = pipeline.execute(intent: intent, manifest_id: "m-hash", mode: "normal")
      expect(out[:result]).to eq(:precondition_failed)
      expect(out[:error]).to eq("expected_pre_hash mismatch")
      expect(File.read(path)).to eq("v1")
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat, RSpec/DescribeMethod

# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
RSpec.describe OllamaAgent::Runtime::KernelPipeline, "rename_file intent" do
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

  it "commits after renaming within the workspace" do
    Dir.mktmpdir("kernel-rename-happy") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      from = File.join(root, "lib", "zebra.txt")
      to_path = File.join(root, "lib", "alpha.txt")
      File.write(from, "moved")
      pre = Digest::SHA256.hexdigest(File.binread(from).b)

      pipeline = build_pipeline(root)
      intent = {
        kind: "rename_file",
        from_path: "lib/zebra.txt",
        to_path: "lib/alpha.txt",
        expected_pre_hash: pre,
        post_conditions: [],
        scopes: []
      }
      out = pipeline.execute(intent: intent, manifest_id: "manifest-rename-ok", mode: "normal")
      expect(out[:result]).to eq(:ok)
      expect(out[:state]).to eq("committed")
      expect(File.exist?(from)).to be(false)
      expect(File.read(to_path)).to eq("moved")
    end
  end

  it "acquires locks in lexicographic scope order (both paths)" do
    Dir.mktmpdir("kernel-rename-locks") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      from = File.join(root, "lib", "zebra.txt")
      File.write(from, "x")
      pre = Digest::SHA256.hexdigest(File.binread(from).b)

      pipeline = build_pipeline(root)
      lm = pipeline.send(:lock_manager)
      seen = []
      allow(lm).to receive(:acquire).and_wrap_original do |m, **kwargs|
        seen << File.basename(kwargs[:scope].to_s)
        m.call(**kwargs)
      end

      intent = {
        kind: "rename_file",
        from_path: "lib/zebra.txt",
        to_path: "lib/alpha.txt",
        expected_pre_hash: pre,
        post_conditions: [],
        scopes: []
      }
      pipeline.execute(intent: intent, manifest_id: "manifest-rename-locks", mode: "normal")
      expect(seen).to eq(%w[alpha.txt zebra.txt])
    end
  end

  it "compensates by reversing the rename when verification fails" do
    Dir.mktmpdir("kernel-rename-comp") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      from = File.join(root, "lib", "src.txt")
      to = File.join(root, "lib", "dest.txt")
      File.write(from, "body")
      pre = Digest::SHA256.hexdigest(File.binread(from).b)

      pipeline = build_pipeline(root, validator: fake_validator(verify_ok: false))
      intent = {
        kind: "rename_file",
        from_path: "lib/src.txt",
        to_path: "lib/dest.txt",
        expected_pre_hash: pre,
        post_conditions: [{ name: "must_fail", command: %w[/bin/true], expect_exit: 0 }],
        scopes: []
      }
      out = pipeline.execute(intent: intent, manifest_id: "manifest-rename-comp", mode: "normal")
      expect(out[:result]).to eq(:error)
      expect(File.file?(from)).to be(true)
      expect(File.read(from)).to eq("body")
      expect(File.exist?(to)).to be(false)
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat, RSpec/DescribeMethod

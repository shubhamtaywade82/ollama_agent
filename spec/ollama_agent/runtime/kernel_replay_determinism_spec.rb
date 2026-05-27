# frozen_string_literal: true

# rubocop:disable RSpec/SpecFilePathFormat -- E1 cross-component replay scenario (see kernel_replay_determinism)
# rubocop:disable Metrics/MethodLength -- small helpers build one deterministic WAL sequence

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::WorkspaceWalReplay, :determinism do
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

  def sentinel
    OllamaAgent::Runtime::CASGuard::NEW_FILE_SENTINEL
  end

  def pre_hash(root, rel)
    abs = File.join(root, rel)
    return sentinel unless File.file?(abs)

    Digest::SHA256.hexdigest(File.binread(abs).b)
  end

  def fingerprint(root)
    OllamaAgent::State::WorkspaceFingerprint.new(
      root: root,
      ignore_under: File.join(root, ".ollama_agent")
    ).compute
  end

  def patch_for(rel, old_line, new_line)
    <<~DIFF
      diff --git a/#{rel} b/#{rel}
      --- a/#{rel}
      +++ b/#{rel}
      @@ -1,1 +1,1 @@
      -#{old_line}
      +#{new_line}
    DIFF
  end

  def run!(pipeline, manifest_id, intent)
    out = pipeline.execute(intent: intent.merge(post_conditions: [], scopes: []), manifest_id: manifest_id,
                           mode: "normal")
    expect(out[:result]).to eq(:ok), -> { "unexpected #{manifest_id}: #{out.inspect}" }
  end

  def run_five_writes(pipeline)
    5.times do |i|
      run!(
        pipeline,
        "m-write-#{i}",
        {
          kind: "atomic_write",
          path: "lib/w#{i}.txt",
          content: "write-#{i}\n",
          expected_pre_hash: sentinel
        }
      )
    end
  end

  def run_three_edits(pipeline, root_a)
    3.times do |i|
      rel = "lib/w#{i}.txt"
      run!(
        pipeline,
        "m-edit-#{i}",
        {
          kind: "edit_file",
          path: rel,
          expected_pre_hash: pre_hash(root_a, rel),
          edits: [{ search: "write-#{i}\n", replace: "edited-#{i}\n" }]
        }
      )
    end
  end

  def run_two_patches(pipeline, root_a)
    run!(
      pipeline,
      "m-patch-1",
      {
        kind: "apply_patch",
        path: "lib/w3.txt",
        patch: patch_for("lib/w3.txt", "write-3", "patched-3"),
        expected_pre_hash: pre_hash(root_a, "lib/w3.txt")
      }
    )
    run!(
      pipeline,
      "m-patch-2",
      {
        kind: "apply_patch",
        path: "lib/w4.txt",
        patch: patch_for("lib/w4.txt", "write-4", "patched-4"),
        expected_pre_hash: pre_hash(root_a, "lib/w4.txt")
      }
    )
  end

  def run_delete_w0(pipeline, root_a)
    run!(
      pipeline,
      "m-del",
      {
        kind: "delete_file",
        path: "lib/w0.txt",
        expected_pre_hash: pre_hash(root_a, "lib/w0.txt")
      }
    )
  end

  it "replays global mutations to the same workspace tree hash" do
    Dir.mktmpdir("determinism-a") do |root_a|
      FileUtils.mkdir_p(File.join(root_a, "lib"))
      pipeline = build_pipeline(root_a)
      run_five_writes(pipeline)
      run_three_edits(pipeline, root_a)
      run_two_patches(pipeline, root_a)
      run_delete_w0(pipeline, root_a)
      hash_a = fingerprint(root_a)

      Dir.mktmpdir("determinism-b") do |root_b|
        FileUtils.mkdir_p(File.join(root_b, ".ollama_agent"))
        FileUtils.cp_r(File.join(root_a, ".ollama_agent", "kernel"), File.join(root_b, ".ollama_agent"))

        described_class.new(
          workspace_root: root_b,
          event_store_db_path: File.join(root_b, ".ollama_agent", "kernel", "event_store.db"),
          blob_store_kernel_dir: File.join(root_b, ".ollama_agent", "kernel")
        ).replay!

        expect(fingerprint(root_b)).to eq(hash_a)
      end
    end
  end
end

# rubocop:enable RSpec/SpecFilePathFormat, Metrics/MethodLength

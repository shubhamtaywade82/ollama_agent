# frozen_string_literal: true

require "spec_helper"
require "digest"

RSpec.describe OllamaAgent::Runtime::AtomicMutator do
  def sha256_hex(str)
    Digest::SHA256.hexdigest(str.b)
  end

  def kernel(workspace)
    registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: workspace)
    wal = OllamaAgent::Runtime::WAL.new(OllamaAgent::Runtime::EventStore.new(registry.event_store))
    fence = OllamaAgent::Runtime::FencingAllocator.new(registry.runtime)
    [wal, fence]
  end

  def build_mutator(workspace, yaml)
    wal, fence = kernel(workspace)
    index = OllamaAgent::Security::OwnershipCompiler.new.compile(yaml_string: yaml)
    mutator = described_class.new(
      workspace_root: workspace,
      ownership_index: index,
      fencing_allocator: fence,
      wal: wal
    )
    [mutator, fence]
  end

  let(:minimal_rules) do
    <<~YAML
      rules:
        - prefix: lib
          owner: libraries
          mutable_in_modes: [normal, replay, validation, dry_run]
          criticality: routine
          children: []
        - prefix: vault
          owner: secrets
          mutable_in_modes: [normal]
          criticality: routine
          forbidden: true
          children: []
        - prefix: mig
          owner: data
          mutable_in_modes: [normal]
          criticality: critical
          children: []
    YAML
  end

  it "writes a new file atomically" do
    Dir.mktmpdir("atomic-mutator-new") do |workspace|
      mutator, fence = build_mutator(workspace, minimal_rules)
      rel = "lib/new.rb"
      absolute = File.join(workspace, rel)
      token = fence.allocate(scope: absolute)

      outcome = mutator.write(
        path: rel,
        content: "first",
        mode: "normal",
        fencing_token: token,
        expected_pre_hash: OllamaAgent::Runtime::CASGuard::NEW_FILE_SENTINEL,
        intent_hash: "intent-new-1",
        manifest_id: "m1",
        logical_stamp: "0:1"
      )

      expect(outcome).to eq(:written)
      expect(File.read(absolute)).to eq("first")
    end
  end

  it "overwrites an existing file when the precondition hash matches" do
    Dir.mktmpdir("atomic-mutator-overwrite") do |workspace|
      mutator, fence = build_mutator(workspace, minimal_rules)
      rel = "lib/existing.rb"
      absolute = File.join(workspace, rel)
      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, "old")
      pre = sha256_hex("old")
      token = fence.allocate(scope: absolute)

      outcome = mutator.write(
        path: rel,
        content: "new",
        mode: "normal",
        fencing_token: token,
        expected_pre_hash: pre,
        intent_hash: "intent-ov-1",
        manifest_id: "m1",
        logical_stamp: "0:2"
      )

      expect(outcome).to eq(:written)
      expect(File.read(absolute)).to eq("new")
    end
  end

  it "preserves the destination permission bits on overwrite" do
    Dir.mktmpdir("atomic-mutator-mode") do |workspace|
      mutator, fence = build_mutator(workspace, minimal_rules)
      rel = "lib/mode.rb"
      absolute = File.join(workspace, rel)
      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, "old")
      File.chmod(0o644, absolute)
      pre = sha256_hex("old")
      token = fence.allocate(scope: absolute)

      expect(
        mutator.write(
          path: rel,
          content: "new",
          mode: "normal",
          fencing_token: token,
          expected_pre_hash: pre,
          intent_hash: "intent-mode-1",
          manifest_id: "m1",
          logical_stamp: "0:2b"
        )
      ).to eq(:written)

      expect(File.stat(absolute).mode & 0o7777).to eq(0o644)
    end
  end

  it "returns :forbidden for paths blocked by ownership" do
    Dir.mktmpdir("atomic-mutator-forbidden") do |workspace|
      mutator, fence = build_mutator(workspace, minimal_rules)
      rel = "vault/secret.txt"
      absolute = File.join(workspace, rel)
      token = fence.allocate(scope: absolute)

      outcome = mutator.write(
        path: rel,
        content: "nope",
        mode: "normal",
        fencing_token: token,
        expected_pre_hash: OllamaAgent::Runtime::CASGuard::NEW_FILE_SENTINEL,
        intent_hash: "intent-fb-1",
        manifest_id: "m1",
        logical_stamp: "0:3"
      )

      expect(outcome).to eq(:forbidden)
      expect(File.exist?(absolute)).to be(false)
    end
  end

  it "returns :forbidden when a critical path lacks a supervisor lease" do
    Dir.mktmpdir("atomic-mutator-lease") do |workspace|
      mutator, fence = build_mutator(workspace, minimal_rules)
      rel = "mig/001_x.rb"
      absolute = File.join(workspace, rel)
      token = fence.allocate(scope: absolute)

      outcome = mutator.write(
        path: rel,
        content: "up",
        mode: "normal",
        fencing_token: token,
        expected_pre_hash: OllamaAgent::Runtime::CASGuard::NEW_FILE_SENTINEL,
        intent_hash: "intent-cr-1",
        manifest_id: "m1",
        logical_stamp: "0:4",
        supervisor_lease: false
      )

      expect(outcome).to eq(:forbidden)
      expect(File.exist?(absolute)).to be(false)
    end
  end

  it "allows critical paths when supervisor_lease is true" do
    Dir.mktmpdir("atomic-mutator-lease-ok") do |workspace|
      mutator, fence = build_mutator(workspace, minimal_rules)
      rel = "mig/001_x.rb"
      absolute = File.join(workspace, rel)
      token = fence.allocate(scope: absolute)

      outcome = mutator.write(
        path: rel,
        content: "up",
        mode: "normal",
        fencing_token: token,
        expected_pre_hash: OllamaAgent::Runtime::CASGuard::NEW_FILE_SENTINEL,
        intent_hash: "intent-cr-2",
        manifest_id: "m1",
        logical_stamp: "0:5",
        supervisor_lease: true
      )

      expect(outcome).to eq(:written)
      expect(File.read(absolute)).to eq("up")
    end
  end

  it "returns :stale_token when the fencing lease does not match" do
    Dir.mktmpdir("atomic-mutator-stale") do |workspace|
      mutator, fence = build_mutator(workspace, minimal_rules)
      rel = "lib/stale.rb"
      absolute = File.join(workspace, rel)
      fence.allocate(scope: absolute)

      outcome = mutator.write(
        path: rel,
        content: "x",
        mode: "normal",
        fencing_token: 999,
        expected_pre_hash: OllamaAgent::Runtime::CASGuard::NEW_FILE_SENTINEL,
        intent_hash: "intent-st-1",
        manifest_id: "m1",
        logical_stamp: "0:6"
      )

      expect(outcome).to eq(:stale_token)
      expect(File.exist?(absolute)).to be(false)
    end
  end

  it "returns :precondition_failed when the content hash does not match" do
    Dir.mktmpdir("atomic-mutator-pre") do |workspace|
      mutator, fence = build_mutator(workspace, minimal_rules)
      rel = "lib/wrong.rb"
      absolute = File.join(workspace, rel)
      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, "body")
      token = fence.allocate(scope: absolute)

      outcome = mutator.write(
        path: rel,
        content: "next",
        mode: "normal",
        fencing_token: token,
        expected_pre_hash: sha256_hex("not-body"),
        intent_hash: "intent-pre-1",
        manifest_id: "m1",
        logical_stamp: "0:7"
      )

      expect(outcome).to eq(:precondition_failed)
      expect(File.read(absolute)).to eq("body")
    end
  end

  it "returns :duplicate when the intent_hash was already recorded" do
    Dir.mktmpdir("atomic-mutator-dup") do |workspace|
      mutator, fence = build_mutator(workspace, minimal_rules)
      rel = "lib/dup.rb"
      absolute = File.join(workspace, rel)
      intent = "intent-dup-shared"

      first_token = fence.allocate(scope: absolute)
      expect(
        mutator.write(
          path: rel,
          content: "one",
          mode: "normal",
          fencing_token: first_token,
          expected_pre_hash: OllamaAgent::Runtime::CASGuard::NEW_FILE_SENTINEL,
          intent_hash: intent,
          manifest_id: "m1",
          logical_stamp: "0:8"
        )
      ).to eq(:written)

      second_token = fence.allocate(scope: absolute)
      outcome = mutator.write(
        path: rel,
        content: "two",
        mode: "normal",
        fencing_token: second_token,
        expected_pre_hash: sha256_hex("one"),
        intent_hash: intent,
        manifest_id: "m1",
        logical_stamp: "0:9"
      )

      expect(outcome).to eq(:duplicate)
      expect(File.read(absolute)).to eq("one")
    end
  end

  it "returns :inode_swapped when the destination inode changes mid-flight" do
    Dir.mktmpdir("atomic-mutator-inode") do |workspace|
      mutator, fence = build_mutator(workspace, minimal_rules)
      rel = "lib/inode.rb"
      absolute = File.expand_path(File.join(workspace, rel))
      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, "stable")
      token = fence.allocate(scope: absolute)

      first_stat = instance_double(File::Stat, dev: 1, ino: 100, directory?: false)
      second_stat = instance_double(File::Stat, dev: 1, ino: 200, directory?: false)
      inode_calls = 0
      allow(File).to receive(:lstat).and_wrap_original do |original, path|
        if File.expand_path(path.to_s) == absolute
          inode_calls += 1
          inode_calls == 1 ? first_stat : second_stat
        else
          original.call(path)
        end
      end

      outcome = mutator.write(
        path: rel,
        content: "race",
        mode: "normal",
        fencing_token: token,
        expected_pre_hash: sha256_hex("stable"),
        intent_hash: "intent-ino-1",
        manifest_id: "m1",
        logical_stamp: "0:10"
      )

      expect(outcome).to eq(:inode_swapped)
      expect(File.read(absolute)).to eq("stable")
    end
  end

  it "leaves the destination unchanged when a child dies after fsyncing a temp file", :fork do
    skip "Process.fork is unavailable" unless Process.respond_to?(:fork)

    Dir.mktmpdir("atomic-mutator-kill") do |workspace|
      dest = File.join(workspace, "out.txt")
      File.write(dest, "orig")
      parent = File.dirname(dest)
      temp = File.join(parent, "out.txt.kill.tmp")

      pid = fork do
        File.open(temp, File::WRONLY | File::CREAT | File::TRUNC | File::BINARY) do |io|
          io.write("partial")
          io.fsync
        end
        Process.kill("KILL", Process.pid)
      end

      Process.waitpid(pid)
      expect(File.read(dest)).to eq("orig")
    end
  end
end

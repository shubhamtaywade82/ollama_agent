# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::CompensationEngine do
  def kernel_dir(root)
    File.join(root, ".ollama_agent", "kernel")
  end

  it "restores a file from a blob snapshot" do
    Dir.mktmpdir("comp-restore") do |root|
      registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
      db = registry.runtime
      blob = OllamaAgent::Runtime::BlobStore.new(kernel_dir: kernel_dir(root))
      manifest = OllamaAgent::Runtime::CompensationManifest.new(db)
      hex = blob.put("before")
      target = File.join(root, "lib", "file.rb")
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite(target, "after")

      manifest.record(
        manifest_id: "m1",
        path: target,
        op: "atomic_write",
        pre_blob_sha: hex,
        pre_existed: 1,
        fencing_token: 1,
        logical_stamp: "1"
      )

      eng = described_class.new(
        blob_store: blob,
        compensation_manifest: manifest,
        atomic_mutator: instance_double(OllamaAgent::Runtime::AtomicMutator),
        fencing_allocator: instance_double(OllamaAgent::Runtime::FencingAllocator)
      )
      out = eng.compensate(manifest_id: "m1", logical_stamp: "x")
      expect(out[:errors]).to be_empty
      expect(out[:restored]).to eq(1)
      expect(File.binread(target)).to eq("before")
      expect(manifest.each_unapplied(manifest_id: "m1").to_a).to be_empty
    end
  end

  it "unlinks a path when pre_existed was 0" do
    Dir.mktmpdir("comp-unlink") do |root|
      registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
      db = registry.runtime
      blob = OllamaAgent::Runtime::BlobStore.new(kernel_dir: kernel_dir(root))
      manifest = OllamaAgent::Runtime::CompensationManifest.new(db)
      target = File.join(root, "new.rb")
      File.binwrite(target, "x")

      manifest.record(
        manifest_id: "m2",
        path: target,
        op: "atomic_write",
        pre_blob_sha: nil,
        pre_existed: 0,
        fencing_token: 1,
        logical_stamp: "1"
      )

      eng = described_class.new(
        blob_store: blob,
        compensation_manifest: manifest,
        atomic_mutator: instance_double(OllamaAgent::Runtime::AtomicMutator),
        fencing_allocator: instance_double(OllamaAgent::Runtime::FencingAllocator)
      )
      out = eng.compensate(manifest_id: "m2", logical_stamp: "x")
      expect(out[:errors]).to be_empty
      expect(out[:missing]).to eq(1)
      expect(File.exist?(target)).to be(false)
    end
  end

  it "continues after a row fails and resumes remaining unapplied rows on the next run" do
    Dir.mktmpdir("comp-resume") do |root|
      registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
      db = registry.runtime
      blob = OllamaAgent::Runtime::BlobStore.new(kernel_dir: kernel_dir(root))
      manifest = OllamaAgent::Runtime::CompensationManifest.new(db)
      good_hex = blob.put("ok")
      bad_hex = "f" * 64
      p1 = File.join(root, "a.txt")
      p2 = File.join(root, "b.txt")
      FileUtils.mkdir_p(File.dirname(p1))

      manifest.record(
        manifest_id: "m3",
        path: p1,
        op: "atomic_write",
        pre_blob_sha: bad_hex,
        pre_existed: 1,
        fencing_token: 1,
        logical_stamp: "1"
      )
      manifest.record(
        manifest_id: "m3",
        path: p2,
        op: "atomic_write",
        pre_blob_sha: good_hex,
        pre_existed: 1,
        fencing_token: 2,
        logical_stamp: "2"
      )

      eng = described_class.new(
        blob_store: blob,
        compensation_manifest: manifest,
        atomic_mutator: instance_double(OllamaAgent::Runtime::AtomicMutator),
        fencing_allocator: instance_double(OllamaAgent::Runtime::FencingAllocator)
      )

      first = eng.compensate(manifest_id: "m3", logical_stamp: "a")
      expect(first[:restored]).to eq(1)
      expect(first[:errors].size).to eq(1)
      expect(manifest.each_unapplied(manifest_id: "m3").to_a.size).to eq(1)

      blob.put("ok") # ensure good_hex still valid
      second = eng.compensate(manifest_id: "m3", logical_stamp: "b")
      expect(second[:errors].size).to eq(1)
      expect(manifest.each_unapplied(manifest_id: "m3").to_a.size).to eq(1)

      fixed = blob.put("fixed")
      db.execute("UPDATE compensations SET pre_blob_sha = ? WHERE path = ?", [fixed, p1])
      third = eng.compensate(manifest_id: "m3", logical_stamp: "c")
      expect(third[:errors]).to be_empty
      expect(manifest.each_unapplied(manifest_id: "m3").to_a).to be_empty
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::CompensationManifest do
  def with_db
    Dir.mktmpdir("comp-manifest") do |root|
      registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
      yield registry.runtime
    end
  end

  it "records rows, yields unapplied newest-first, and marks applied" do
    with_db do |db|
      m = described_class.new(db)
      id1 = m.record(
        manifest_id: "m1",
        path: "/tmp/a",
        op: "atomic_write",
        pre_blob_sha: "a" * 64,
        pre_existed: 1,
        fencing_token: 1,
        logical_stamp: "s1"
      )
      id2 = m.record(
        manifest_id: "m1",
        path: "/tmp/b",
        op: "atomic_write",
        pre_blob_sha: nil,
        pre_existed: 0,
        fencing_token: 2,
        logical_stamp: "s2"
      )
      expect(id2).to be > id1

      ids = m.each_unapplied(manifest_id: "m1").map { |r| r["id"].to_i }
      expect(ids).to eq([id2, id1])

      m.mark_applied(id: id2)
      remaining = m.each_unapplied(manifest_id: "m1").map { |r| r["id"].to_i }
      expect(remaining).to eq([id1])
    end
  end

  it "assigns a new id on each record (not deduped)" do
    with_db do |db|
      m = described_class.new(db)
      attrs = {
        manifest_id: "m1",
        path: "/p",
        op: "x",
        pre_blob_sha: nil,
        pre_existed: 0,
        fencing_token: 0,
        logical_stamp: "z"
      }
      a = m.record(**attrs)
      b = m.record(**attrs)
      expect(b).to be > a
    end
  end
end

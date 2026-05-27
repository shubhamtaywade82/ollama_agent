# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::IntentTranslator do
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

  it "maps write_file to atomic_write with expected_pre_hash" do
    Dir.mktmpdir("intent-tr-write") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "w.txt")
      File.write(path, "body")
      expected = Digest::SHA256.hexdigest(File.binread(path).b)

      tr = described_class.new(workspace_root: root)
      intent = tr.translate(
        tool_call: { "name" => "write_file", "arguments" => { "path" => "lib/w.txt", "content" => "new" } }
      )
      expect(intent[:kind]).to eq("atomic_write")
      expect(intent[:path]).to eq("lib/w.txt")
      expect(intent[:content]).to eq("new")
      expect(intent[:expected_pre_hash]).to eq(expected)
    end
  end

  it "maps write_file for a missing file to new-file sentinel" do
    Dir.mktmpdir("intent-tr-new") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      tr = described_class.new(workspace_root: root)
      intent = tr.translate(
        tool_call: { "name" => "write_file", "arguments" => { "path" => "lib/new.txt", "content" => "x" } }
      )
      expect(intent[:expected_pre_hash]).to eq(OllamaAgent::Runtime::CASGuard::NEW_FILE_SENTINEL)
    end
  end

  it "maps edit_file with search/replace to edit_file intent" do
    Dir.mktmpdir("intent-tr-edit") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "e.txt")
      File.write(path, "hello")
      pre = Digest::SHA256.hexdigest(File.binread(path).b)

      tr = described_class.new(workspace_root: root)
      intent = tr.translate(
        tool_call: {
          "name" => "edit_file",
          "arguments" => { "path" => "lib/e.txt", "search" => "ello", "replace" => "i" }
        }
      )
      expect(intent[:kind]).to eq("edit_file")
      expect(intent[:edits]).to eq([{ search: "ello", replace: "i" }])
      expect(intent[:expected_pre_hash]).to eq(pre)
    end
  end

  it "maps edit_file with diff to apply_patch intent (real tool shape)" do
    Dir.mktmpdir("intent-tr-diff") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "d.txt")
      File.write(path, "a\nb\n")
      pre = Digest::SHA256.hexdigest(File.binread(path).b)
      diff = <<~DIFF
        diff --git a/lib/d.txt b/lib/d.txt
        --- a/lib/d.txt
        +++ b/lib/d.txt
        @@ -1,2 +1,2 @@
         a
        -b
        +c
      DIFF

      tr = described_class.new(workspace_root: root)
      intent = tr.translate(
        tool_call: { "name" => "edit_file", "arguments" => { "path" => "lib/d.txt", "diff" => diff } }
      )
      expect(intent[:kind]).to eq("apply_patch")
      expect(intent[:path]).to eq("lib/d.txt")
      expect(intent[:patch]).to include("diff --git")
      expect(intent[:expected_pre_hash]).to eq(pre)
    end
  end

  it "maps apply_patch with only patch string by parsing path from headers" do
    Dir.mktmpdir("intent-tr-patch") do |root|
      OllamaAgent::Security::OwnershipCompiler.new.compile(yaml_string: minimal_owners_yaml)
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "p.txt")
      File.write(path, "x")
      pre = Digest::SHA256.hexdigest(File.binread(path).b)
      diff = <<~DIFF
        diff --git a/lib/p.txt b/lib/p.txt
        --- a/lib/p.txt
        +++ b/lib/p.txt
        @@ -1,1 +1,1 @@
        -x
        +y
      DIFF

      tr = described_class.new(workspace_root: root)
      intent = tr.translate(tool_call: { "name" => "apply_patch", "arguments" => { "patch" => diff } })
      expect(intent[:kind]).to eq("apply_patch")
      expect(intent[:path]).to eq("lib/p.txt")
      expect(intent[:expected_pre_hash]).to eq(pre)
    end
  end

  it "maps delete_file to delete_file intent with scopes" do
    Dir.mktmpdir("intent-tr-del") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      path = File.join(root, "lib", "d.txt")
      File.write(path, "x")
      pre = Digest::SHA256.hexdigest(File.binread(path).b)

      tr = described_class.new(workspace_root: root)
      intent = tr.translate(
        tool_call: { "name" => "delete_file", "arguments" => { "path" => "lib/d.txt" } }
      )
      expect(intent[:kind]).to eq("delete_file")
      expect(intent[:path]).to eq("lib/d.txt")
      expect(intent[:expected_pre_hash]).to eq(pre)
      expect(intent[:scopes]).to eq(["lib/d.txt"])
    end
  end

  it "maps rename_file to rename_file intent with sorted scopes" do
    Dir.mktmpdir("intent-tr-rename") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      from = File.join(root, "lib", "z.txt")
      File.write(from, "body")
      pre = Digest::SHA256.hexdigest(File.binread(from).b)

      tr = described_class.new(workspace_root: root)
      intent = tr.translate(
        tool_call: {
          "name" => "rename_file",
          "arguments" => { "from" => "lib/z.txt", "to" => "lib/a.txt" }
        }
      )
      expect(intent[:kind]).to eq("rename_file")
      expect(intent[:from_path]).to eq("lib/z.txt")
      expect(intent[:to_path]).to eq("lib/a.txt")
      expect(intent[:expected_pre_hash]).to eq(pre)
      expect(intent[:scopes]).to eq(%w[lib/a.txt lib/z.txt])
    end
  end

  it "maps move_file like rename_file" do
    Dir.mktmpdir("intent-tr-move") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      from = File.join(root, "lib", "old.txt")
      File.write(from, "m")
      pre = Digest::SHA256.hexdigest(File.binread(from).b)

      tr = described_class.new(workspace_root: root)
      intent = tr.translate(
        tool_call: {
          "name" => "move_file",
          "arguments" => { "from" => "lib/old.txt", "to" => "lib/new.txt" }
        }
      )
      expect(intent[:kind]).to eq("rename_file")
      expect(intent[:from_path]).to eq("lib/old.txt")
      expect(intent[:to_path]).to eq("lib/new.txt")
      expect(intent[:expected_pre_hash]).to eq(pre)
      expect(intent[:scopes]).to eq(%w[lib/new.txt lib/old.txt])
    end
  end
end

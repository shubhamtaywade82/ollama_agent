# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::DiffPathValidator do
  let(:root) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(root)
  end

  describe ".call" do
    it "returns nil when +++ paths match the target" do
      diff = <<~DIFF
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -a
        +b
      DIFF

      expect(described_class.call(diff, root, "README.md")).to be_nil
    end

    it "returns an error when +++ names a different file than path" do
      diff = <<~DIFF
        --- a/lib/example.rb
        +++ b/lib/example.rb
        @@ -1 +1 @@
        -old
        +new
      DIFF

      result = described_class.call(diff, root, "README.md")
      expect(result).to include("do not match")
      expect(result).to include("lib/example.rb")
    end

    it "rejects an empty diff" do
      expect(described_class.call("", root, "README.md")).to eq("Diff is empty.")
    end

    it "rejects a diff with no +++ lines" do
      expect(described_class.call("not a unified diff\n", root, "README.md")).to include("+++")
    end

    it "rejects a diff with only --- and +++ (no hunks)" do
      diff = <<~DIFF
        --- a/README.md
        +++ b/README.md
      DIFF

      expect(described_class.call(diff, root, "README.md")).to include("hunk header")
    end

    it "passes structure when @@ is present even if the hunk body is empty (patch dry-run rejects later)" do
      diff = <<~DIFF
        --- a/README.md
        +++ b/README.md
        @@ -1,3 +1,3 @@
      DIFF

      expect(described_class.call(diff, root, "README.md")).to be_nil
    end

    it "treats literal \\n in a single string as newlines" do
      raw = '--- a/README.md\n+++ b/README.md'
      expect(described_class.call(raw, root, "README.md")).to include("hunk header")
    end

    it "rejects when @@ appears before the first +++ line" do
      diff = <<~DIFF
        --- a/README.md
        @@ -1,3 +1,3 @@
        # Readme
        --- b/README.md
        +++ b/README.md
      DIFF

      expect(described_class.call(diff, root, "README.md")).to include("+++ b/")
    end

    it "rejects legacy context-diff hunks like --- N,M ----" do
      diff = <<~DIFF
        --- a/README.md
        +++ b/README.md
        --- 2,1 ----
        -old
        +new
      DIFF

      expect(described_class.call(diff, root, "README.md")).to include("@@")
    end
  end

  describe ".normalize_diff" do
    it "strips trailing commas on --- and +++ header lines" do
      raw = <<~DIFF
        --- a/README.md,
        +++ b/README.md,
        @@ -1 +1 @@
        -a
        +b
      DIFF
      normalized = described_class.normalize_diff(raw)
      expect(normalized.lines[0].strip).to eq("--- a/README.md")
      expect(normalized.lines[1].strip).to eq("+++ b/README.md")
    end

    it "expands escaped newlines when there are no real line breaks" do
      raw = '--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new'
      normalized = described_class.normalize_diff(raw)
      expect(normalized).to include("@@")
      expect(described_class.call(normalized, root, "x")).to be_nil
    end

    it "splits --- a/file @@ when glued on one line" do
      raw = "--- a/README.md @@ -1,3 +1,3 @@\n-old\n+new"
      normalized = described_class.normalize_diff(raw)
      expect(normalized.lines[0].strip).to end_with(".md")
      expect(normalized).to include("\n@@")
    end

    it "strips Cursor-style *** End Patch / *** Begin Patch lines" do
      raw = <<~DIFF
        --- a/x.md
        +++ b/x.md
        @@ -1 +1 @@
        -a
        +b
        *** End Patch
      DIFF
      normalized = described_class.normalize_diff(raw)
      expect(normalized).not_to include("***")
      expect(described_class.call(normalized, root, "x.md")).to be_nil
    end

    it "does not expand literal \\n when the string already contains real newlines" do
      raw = "--- a/f.md\\n+++ b/f.md\n@@ -1,1 +1,1 @@\n-a\n+b"
      normalized = described_class.normalize_diff(raw)
      expect(normalized).to include("+++")
      expect(normalized).to include("\\n")
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "OllamaAgent::SandboxedTools" do
  def patch_supports_dry_run?
    out, = Open3.capture2e("patch", "--help")
    out.include?("dry-run")
  end

  describe "#execute_tool" do
    let(:tmpdir) { Dir.mktmpdir }
    let(:agent) { OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false) }

    after do
      FileUtils.remove_entry(tmpdir)
    end

    it "returns a clear error when edit_file path is missing" do
      result = agent.send(:execute_tool, "edit_file", { "diff" => "x" })
      expect(result).to include("Missing required").and include("path")
    end

    it "merges nested parameters into tool arguments" do
      skip "patch --dry-run not supported" unless patch_supports_dry_run?

      File.write(File.join(tmpdir, "README.md"), "hi\n")
      diff = <<~DIFF
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -hi
        +hello
      DIFF
      args = { "parameters" => { "path" => "README.md", "diff" => diff } }
      result = agent.send(:execute_tool, "edit_file", args)
      expect(result).to eq("Patch applied successfully.")
    end
  end

  describe "#edit_file" do
    it "returns a dry-run error without prompting when the diff does not match the file" do
      skip "patch --dry-run not supported" unless patch_supports_dry_run?

      tmpdir = Dir.mktmpdir
      File.write(File.join(tmpdir, "README.md"), "Hello\n")

      agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: true)
      diff = <<~DIFF
        --- a/README.md
        +++ b/README.md
        @@ -1,3 +1,3 @@
        -old
        +new
      DIFF

      result = agent.send(:edit_file, "README.md", diff)
      expect(result).to include("Patch does not apply")
    ensure
      FileUtils.remove_entry(tmpdir)
    end
  end
end

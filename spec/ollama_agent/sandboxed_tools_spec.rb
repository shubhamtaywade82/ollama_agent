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

  describe "#read_file" do
    it "returns only the requested line range when start_line and end_line are set" do
      tmpdir = Dir.mktmpdir
      File.write(File.join(tmpdir, "slice.rb"), "a\nb\nc\nd\n")
      agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false)
      out = agent.send(:read_file, "slice.rb", start_line: 2, end_line: 3)
      expect(out).to eq("b\nc\n")
    ensure
      FileUtils.remove_entry(tmpdir)
    end

    it "rejects a full read when the file is larger than OLLAMA_AGENT_MAX_READ_FILE_BYTES" do
      tmpdir = Dir.mktmpdir
      ENV["OLLAMA_AGENT_MAX_READ_FILE_BYTES"] = "10"
      File.write(File.join(tmpdir, "big.txt"), "x" * 20)
      agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false)
      out = agent.send(:read_file, "big.txt")
      expect(out).to include("max size").and include("10")
    ensure
      ENV.delete("OLLAMA_AGENT_MAX_READ_FILE_BYTES")
      FileUtils.remove_entry(tmpdir)
    end
  end

  describe "search_code Ruby index modes" do
    let(:fixture_root) { File.expand_path("../fixtures/ruby_index", __dir__) }

    it "builds the Ruby index once while OLLAMA_AGENT_INDEX_REBUILD stays set" do
      allow(OllamaAgent::RubyIndex).to receive(:build).and_call_original
      ENV["OLLAMA_AGENT_INDEX_REBUILD"] = "1"
      agent = OllamaAgent::Agent.new(root: fixture_root, confirm_patches: false)
      agent.send(:execute_tool, "search_code", { "pattern" => "a", "mode" => "method" })
      agent.send(:execute_tool, "search_code", { "pattern" => "b", "mode" => "method" })
      expect(OllamaAgent::RubyIndex).to have_received(:build).once
    ensure
      ENV.delete("OLLAMA_AGENT_INDEX_REBUILD")
    end

    it "returns formatted method rows for mode method" do
      agent = OllamaAgent::Agent.new(root: fixture_root, confirm_patches: false)
      out = agent.send(:execute_tool, "search_code", { "pattern" => "instance_method", "mode" => "method" })
      expect(out).to include("instance_method")
      expect(out).to include("nested.rb")
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

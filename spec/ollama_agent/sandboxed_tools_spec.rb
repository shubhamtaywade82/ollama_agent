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

    it "rejects edit_file when the agent is read-only" do
      agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false, read_only: true)
      result = agent.send(:execute_tool, "edit_file", { "path" => "x.rb", "diff" => "---\n" })
      expect(result).to include("read-only")
    end

    it "returns a clear error when patch is not available" do
      File.write(File.join(tmpdir, "README.md"), "x\n")
      allow(agent).to receive(:patch_available?).and_return(false)
      diff = <<~DIFF
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -x
        +y
      DIFF
      result = agent.send(:execute_tool, "edit_file", { "path" => "README.md", "diff" => diff })
      expect(result).to include("Error:").and include("patch")
    end

    it "rejects diffs that match forbidden patterns" do
      skip "patch --dry-run not supported" unless patch_supports_dry_run?

      File.write(File.join(tmpdir, "README.md"), "hi\n")
      diff = <<~DIFF
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -hi
        +eval("x")
      DIFF
      agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false)
      result = agent.send(:execute_tool, "edit_file", { "path" => "README.md", "diff" => diff })
      expect(result).to include("forbidden")
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

    context "write_file" do
      it "creates a new file under the project root" do
        agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false)
        result = agent.send(:execute_tool, "write_file", { "path" => "new.rb", "content" => "# hello\n" })
        expect(result).to eq("Written: new.rb")
        expect(File.read(File.join(tmpdir, "new.rb"))).to eq("# hello\n")
      end

      it "overwrites an existing file" do
        File.write(File.join(tmpdir, "existing.rb"), "old\n")
        agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false)
        agent.send(:execute_tool, "write_file", { "path" => "existing.rb", "content" => "new\n" })
        expect(File.read(File.join(tmpdir, "existing.rb"))).to eq("new\n")
      end

      it "rejects paths outside the project root" do
        agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false)
        result = agent.send(:execute_tool, "write_file", { "path" => "../../etc/passwd", "content" => "x" })
        expect(result).to include("project root")
      end

      it "is disabled in read-only mode" do
        agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false, read_only: true)
        result = agent.send(:execute_tool, "write_file", { "path" => "f.rb", "content" => "x" })
        expect(result).to include("read-only")
      end

      it "returns an error when path argument is missing" do
        agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false)
        result = agent.send(:execute_tool, "write_file", { "content" => "x" })
        expect(result).to include("Missing required").and include("path")
      end

      it "returns an error when content argument is missing" do
        agent = OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false)
        result = agent.send(:execute_tool, "write_file", { "path" => "f.rb" })
        expect(result).to include("Missing required").and include("content")
      end
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
      expect(out).to include("file too large").and include("10").and include("start_line")
    ensure
      ENV.delete("OLLAMA_AGENT_MAX_READ_FILE_BYTES")
      FileUtils.remove_entry(tmpdir)
    end
  end

  describe "search_code (text mode)" do
    let(:search_tmp) { Dir.mktmpdir }
    let(:search_agent) { OllamaAgent::Agent.new(root: search_tmp, confirm_patches: false) }

    after do
      FileUtils.remove_entry(search_tmp)
    end

    it "returns a clear error when neither rg nor grep is available" do
      allow(search_agent).to receive_messages(rg_available?: false, grep_available?: false)
      out = search_agent.send(:execute_tool, "search_code", { "pattern" => "foo", "directory" => "." })
      expect(out).to include("ripgrep").and include("grep").and include("Error:")
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

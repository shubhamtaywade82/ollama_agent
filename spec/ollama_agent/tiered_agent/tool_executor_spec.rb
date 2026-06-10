# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::TieredAgent::ToolExecutor do
  subject(:executor) { described_class.new }

  describe "#execute" do
    context "with execute_bash" do
      it "runs a safe shell command and returns stdout" do
        result = executor.execute("execute_bash", "command" => "echo hello")
        expect(result.strip).to eq("hello")
      end

      it "captures stderr output via 2>&1" do
        result = executor.execute("execute_bash", "command" => "ruby -e '$stderr.puts \"stderr_msg\"'")
        expect(result).to include("stderr_msg")
      end

      it "blocks rm -rf" do
        result = executor.execute("execute_bash", "command" => "rm -rf /tmp/fake")
        expect(result).to include("[Blocked]")
      end

      it "blocks rm -fr variant" do
        result = executor.execute("execute_bash", "command" => "rm -fr /tmp/fake")
        expect(result).to include("[Blocked]")
      end

      it "blocks chained ; rm" do
        result = executor.execute("execute_bash", "command" => "ls; rm -f file")
        expect(result).to include("[Blocked]")
      end

      it "blocks piped | rm" do
        result = executor.execute("execute_bash", "command" => "echo file | rm")
        expect(result).to include("[Blocked]")
      end

      it "blocks mkfs commands" do
        result = executor.execute("execute_bash", "command" => "mkfs.ext4 /dev/sda")
        expect(result).to include("[Blocked]")
      end

      it "blocks block device redirects" do
        result = executor.execute("execute_bash", "command" => "echo data > /dev/sda")
        expect(result).to include("[Blocked]")
      end

      it "blocks empty commands" do
        result = executor.execute("execute_bash", "command" => "")
        expect(result).to include("[Blocked]")
      end

      it "returns a system exception message on OS error" do
        allow(executor).to receive(:`).and_raise(Errno::ENOENT, "not found")
        result = executor.execute("execute_bash", "command" => "nonexistent_tool_xyz")
        expect(result).to include("[System Exception]")
      end
    end

    context "with read_source_file" do
      it "returns file contents for an existing file" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "test.txt")
          File.write(path, "hello content")
          result = executor.execute("read_source_file", "path" => path)
          expect(result).to eq("hello content")
        end
      end

      it "returns an error message for a missing file" do
        result = executor.execute("read_source_file", "path" => "/nonexistent/path/file.txt")
        expect(result).to include("[Error]")
        expect(result).to include("not found")
      end
    end

    context "with write_output_file" do
      it "writes content to a file and returns success" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "out.txt")
          result = executor.execute("write_output_file", "path" => path, "data" => "written data")
          expect(result).to include("[Success]")
          expect(File.read(path)).to eq("written data")
        end
      end

      it "creates intermediate directories" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "sub", "dir", "file.txt")
          executor.execute("write_output_file", "path" => path, "data" => "nested")
          expect(File.read(path)).to eq("nested")
        end
      end

      it "returns an error when path is empty" do
        result = executor.execute("write_output_file", "path" => "", "data" => "data")
        expect(result).to include("[Error]")
      end
    end

    context "with an unknown tool name" do
      it "returns a runtime error message" do
        result = executor.execute("unknown_tool", {})
        expect(result).to include("[Runtime Error]")
        expect(result).to include("unknown_tool")
      end
    end
  end
end

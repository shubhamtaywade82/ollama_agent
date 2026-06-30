# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe OllamaAgent::Tools::CopyFile do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }
  let(:src) { File.join(tmpdir, "src.txt") }
  let(:dest) { File.join(tmpdir, "dest.txt") }

  before { File.write(src, "hello") }
  after  { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("copy_file")
    end

    it "is low risk and requires no approval" do
      expect(tool.risk_level).to eq(:low)
      expect(tool.requires_approval).to be(false)
    end

    it "is not read_only safe" do
      expect(tool.read_only_safe).to be(false)
    end
  end

  describe "#call" do
    it "copies a file" do
      result = tool.call({ "src" => "src.txt", "dest" => "dest.txt" }, context: context)
      expect(result).to match(/Copied/)
      expect(File.read(dest)).to eq("hello")
    end

    it "returns an error when source does not exist" do
      result = tool.call({ "src" => "no_such.txt", "dest" => "x.txt" }, context: context)
      expect(result).to include("Error")
    end
  end
end

RSpec.describe OllamaAgent::Tools::DeleteFile do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }
  let(:file) { File.join(tmpdir, "delete_me.txt") }

  before { File.write(file, "bye") }
  after  { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("delete_file")
    end
  end

  describe "#call" do
    it "trashes a file to .trash/" do
      result = tool.call({ "path" => "delete_me.txt" }, context: context)
      expect(result).to match(/Trashed/)
      expect(File).not_to exist(file)
      expect(Dir.glob(File.join(tmpdir, ".trash", "*"))).not_to be_empty
    end

    it "returns error for non-existent file" do
      result = tool.call({ "path" => "nope.txt" }, context: context)
      expect(result).to include("Error")
    end

    it "is blocked in read-only mode" do
      result = tool.call({ "path" => "delete_me.txt" }, context: context.merge(read_only: true))
      expect(result).to match(/read-only/)
    end
  end
end

RSpec.describe OllamaAgent::Tools::MoveFile do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }
  let(:src) { File.join(tmpdir, "old_name.txt") }

  before { File.write(src, "movable") }
  after  { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("move_file")
    end
  end

  describe "#call" do
    it "renames a file" do
      result = tool.call({ "src" => "old_name.txt", "dest" => "new_name.txt" }, context: context)
      expect(result).to match(/Moved/)
      expect(File).not_to exist(src)
      expect(File).to exist(File.join(tmpdir, "new_name.txt"))
    end

    it "returns error for non-existent source" do
      result = tool.call({ "src" => "ghost.txt", "dest" => "x.txt" }, context: context)
      expect(result).to include("Error")
    end

    it "is blocked in read-only mode" do
      result = tool.call({ "src" => "old_name.txt", "dest" => "x.txt" }, context: context.merge(read_only: true))
      expect(result).to match(/read-only/)
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::FilesystemExplorer do
  let(:tmpdir)  { Dir.mktmpdir }
  let(:tool)    { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  def call(path: nil)
    args = path ? { "path" => path } : {}
    tool.call(args, context: context)
  end

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("list_directory_contents")
    end

    it "is low risk and requires no approval" do
      expect(tool.risk_level).to eq(:low)
      expect(tool.requires_approval).to be(false)
    end
  end

  describe "#call" do
    context "with files and subdirectories present" do
      before do
        File.write(File.join(tmpdir, "readme.txt"), "hello")
        Dir.mkdir(File.join(tmpdir, "src"))
        File.write(File.join(tmpdir, "src", "app.rb"), "# app")
      end

      it "lists files with byte sizes" do
        result = call
        expect(result).to include("[FILE] readme.txt")
        expect(result).to include("bytes")
      end

      it "marks subdirectories with [DIR]" do
        result = call
        expect(result).to include("[DIR]  src/")
      end

      it "reports the item count in the header" do
        result = call
        expect(result).to include("2 item(s)")
      end

      it "lists a subdirectory when given a relative path" do
        result = call(path: "src")
        expect(result).to include("[FILE] app.rb")
      end
    end

    context "with an empty directory" do
      it "returns an empty-directory message" do
        result = call
        expect(result).to include("empty")
      end
    end

    context "with a non-existent path" do
      it "returns an error" do
        result = call(path: "no_such_dir")
        expect(result).to include("Error")
        expect(result).to include("does not exist")
      end
    end

    context "with a path that points to a file" do
      before { File.write(File.join(tmpdir, "file.txt"), "x") }

      it "returns an error when the path is a file not a directory" do
        result = call(path: "file.txt")
        expect(result).to include("Error")
        expect(result).to include("not a directory")
      end
    end

    context "path traversal attempts" do
      it "rejects a dotdot traversal" do
        result = call(path: "../../etc")
        expect(result).to include("Error")
        expect(result).to include("Access denied")
      end

      it "rejects an absolute path outside the workspace" do
        result = call(path: "/etc")
        expect(result).to include("Error")
        expect(result).to include("Access denied")
      end

      it "allows a deeply nested relative path inside the workspace" do
        nested = File.join(tmpdir, "a", "b")
        FileUtils.mkdir_p(nested)
        result = call(path: "a/b")
        expect(result).to include("empty").or include("item(s)")
      end
    end

    context "when no path argument is provided" do
      it "defaults to the workspace root" do
        File.write(File.join(tmpdir, "hello.rb"), "x")
        result = tool.call({}, context: context)
        expect(result).to include("[FILE] hello.rb")
      end
    end
  end
end

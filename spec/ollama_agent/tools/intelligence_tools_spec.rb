# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::GetDefinition do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("get_definition")
    end

    it "is read_only safe" do
      expect(tool.read_only_safe).to be(true)
    end
  end

  describe "#call" do
    it "returns error when symbol not found" do
      File.write(File.join(tmpdir, "empty.rb"), "# nothing")
      result = tool.call({ "symbol" => "NonExistent" }, context: context)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:error)
    end

    it "finds a class definition" do
      File.write(File.join(tmpdir, "foo.rb"), <<~RUBY)
        class Foo
          def bar; end
        end
      RUBY
      result = tool.call({ "symbol" => "Foo", "kind" => "class" }, context: context)
      expect(result).to be_a(Hash)
      expect(result[:name]).to eq("Foo")
      expect(result).to have_key(:file)
      expect(result).to have_key(:source)
    end
  end
end

RSpec.describe OllamaAgent::Tools::ListDependencies do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("list_dependencies")
    end
  end

  describe "#call" do
    it "lists requires from a Ruby file" do
      File.write(File.join(tmpdir, "app.rb"), <<~RUBY)
        require "json"
        require_relative "config"
      RUBY
      result = tool.call({ "file" => "app.rb" }, context: context)
      expect(result[:requires]).to include("json", "config")
    end

    it "returns error for non-existent file" do
      result = tool.call({ "file" => "nope.rb" }, context: context)
      expect(result).to include("Error") # the method returns error string, not hash
    end

    it "returns no-deps message when file has no requires" do
      File.write(File.join(tmpdir, "bare.rb"), "x = 1")
      result = tool.call({ "file" => "bare.rb" }, context: context)
      expect(result).to be_a(Hash)
      expect(result[:requires]).to be_empty
    end
  end
end

RSpec.describe OllamaAgent::Tools::SummarizeFile do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("summarize_file")
    end
  end

  describe "#call" do
    it "returns summary for a Ruby file" do
      File.write(File.join(tmpdir, "lib.rb"), <<~RUBY)
        CONST = 1
        class Worker
          def run; end
        end
      RUBY
      result = tool.call({ "path" => "lib.rb" }, context: context)
      expect(result).to be_a(Hash)
      expect(result[:file]).to eq("lib.rb")
    end

    it "returns error for non-existent file" do
      result = tool.call({ "path" => "nope.rb" }, context: context)
      expect(result).to be_a(String)
      expect(result).to include("Error")
    end
  end
end

RSpec.describe OllamaAgent::Tools::CheckArchitecture do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("check_architecture")
    end
  end

  describe "#call" do
    it "detects ActiveRecord leaks in a diff" do
      diff = "+require \"active_record\"\n+ActiveRecord::Base.connection"
      result = tool.call({ "diff" => diff }, context: {})
      expect(result[:count]).to be >= 1
      expect(result[:violations].first[:rule]).to include("Active Record")
    end

    it "detects TODOs in a diff" do
      diff = "+  # TODO: refactor this"
      result = tool.call({ "diff" => diff }, context: {})
      expect(result[:count]).to be >= 1
    end

    it "returns zero violations for clean diff" do
      diff = "+puts \"hello\""
      result = tool.call({ "diff" => diff }, context: {})
      expect(result[:count]).to eq(0)
    end
  end
end

RSpec.describe OllamaAgent::Tools::GenerateDocs do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("generate_docs")
    end
  end

  describe "#call" do
    it "returns a hash with output" do
      Dir.mkdir(File.join(tmpdir, "lib"))
      File.write(File.join(tmpdir, "lib", "app.rb"), "# doc")
      result = tool.call({ "path" => "lib/" }, context: context)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:exit_code)
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::SearchSymbols do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("search_symbols")
    end

    it "is read_only safe" do
      expect(tool.read_only_safe).to be(true)
    end
  end

  describe "#call" do
    it "returns no-symbols message when nothing matches" do
      result = tool.call({ "pattern" => "NonExistentClass999" }, context: context)
      expect(result).to match(/No symbols found/)
    end

    it "requires a pattern" do
      result = tool.call({ "pattern" => "" }, context: context)
      expect(result).to match(/No symbols found|Error/)
    end
  end
end

RSpec.describe OllamaAgent::Tools::FindReferences do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("find_references")
    end
  end

  describe "#call" do
    it "returns no references for non-existent symbol" do
      result = tool.call({ "symbol" => "ZZZNeverDefinedZZZ" }, context: context)
      expect(result).to match(/No references/)
    end

    it "finds references in a file" do
      File.write(File.join(tmpdir, "test.rb"), "puts MyClass.new\nMyClass.call")
      result = tool.call({ "symbol" => "MyClass" }, context: context)
      expect(result).to include("MyClass")
    end

    it "returns error for empty symbol" do
      result = tool.call({ "symbol" => "" }, context: context)
      expect(result).to include("Error")
    end
  end
end

RSpec.describe OllamaAgent::Tools::GrepAst do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("grep_ast")
    end
  end

  describe "#call" do
    it "searches AST nodes in a Ruby file" do
      File.write(File.join(tmpdir, "sample.rb"), "class Foo\n  def bar\n    42\n  end\nend")
      result = tool.call({ "query" => "class", "file" => "sample.rb" }, context: context)
      expect(result).to include("Foo")
    end

    it "returns error for non-existent file" do
      result = tool.call({ "query" => "class", "file" => "nope.rb" }, context: context)
      expect(result).to include("Error")
    end
  end
end

RSpec.describe OllamaAgent::Tools::ListTodos do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("list_todos")
    end
  end

  describe "#call" do
    it "finds TODO comments" do
      File.write(File.join(tmpdir, "a.rb"), "TODO: fix this")
      result = tool.call({}, context: context)
      expect(result).to include("TODO")
    end

    it "returns no-todos message when none exist" do
      File.write(File.join(tmpdir, "clean.rb"), "# all done")
      result = tool.call({}, context: context)
      expect(result).to match(/No TODO/)
    end
  end
end

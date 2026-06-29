# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::RunTests do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("run_tests")
    end
  end

  describe "#call" do
    it "returns a hash with exit_code" do
      result = tool.call({ "framework" => "pytest", "pattern" => "." }, context: context)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:exit_code)
    end

    it "detects rspec when spec/ exists" do
      Dir.mkdir(File.join(tmpdir, "spec"))
      expect(tool.send(:detect_framework, tmpdir)).to eq("rspec")
    end
  end
end

RSpec.describe OllamaAgent::Tools::RunLinter do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("run_linter")
    end
  end

  describe "#call" do
    it "returns a hash" do
      result = tool.call({ "tool" => "ruff", "path" => "." }, context: context)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:tool)
    end
  end
end

RSpec.describe OllamaAgent::Tools::RunTypecheck do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("run_typecheck")
    end
  end

  describe "#call" do
    it "returns a hash" do
      result = tool.call({ "tool" => "mypy", "path" => "." }, context: context)
      expect(result).to be_a(Hash)
    end
  end
end

RSpec.describe OllamaAgent::Tools::RunBenchmark do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("run_benchmark")
    end
  end

  describe "#call" do
    it "returns error when script does not exist" do
      result = tool.call({ "path" => "no_such_bench.rb" }, context: context)
      expect(result).to be_a(String)
      expect(result).to include("Error")
    end
  end
end

RSpec.describe OllamaAgent::Tools::RunCoverage do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("run_coverage")
    end
  end

  describe "#call" do
    it "returns a hash" do
      result = tool.call({ "framework" => "minitest" }, context: context)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:framework)
    end
  end
end

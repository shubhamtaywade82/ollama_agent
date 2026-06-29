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
      result = tool.call({ "framework" => "minitest", "pattern" => "." }, context: context)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:exit_code)
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
    it "returns a hash with exit_code" do
      result = tool.call({ "tool" => "rubocop", "path" => "." }, context: context)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:exit_code)
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
    it "returns a hash with exit_code" do
      result = tool.call({}, context: context)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:exit_code)
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

    it "runs a valid script" do
      File.write(File.join(tmpdir, "bench.rb"), "puts 42")
      result = tool.call({ "ruby" => "ruby", "path" => "bench.rb" }, context: context)
      expect(result[:output]).to include("42")
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
    it "returns a hash without coverage data when none exists" do
      result = tool.call({ "framework" => "minitest" }, context: context)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:framework)
    end
  end
end

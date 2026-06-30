# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::AuditLog do
  let(:tmpdir) { Dir.mktmpdir }
  let(:tool)   { described_class.new }
  let(:context) { { root: tmpdir } }

  after { FileUtils.remove_entry(tmpdir) }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("audit_log")
    end

    it "is read_only safe" do
      expect(tool.read_only_safe).to be(true)
    end
  end

  describe "#call" do
    it "appends a JSONL entry" do
      result = tool.call({ "action" => "test", "details" => { "key" => "val" } }, context: context)
      expect(result).to match(/Logged/)
      log = File.read(File.join(tmpdir, ".agent_audit.jsonl"))
      expect(log).to include("test")
      expect(log).to include("val")
    end
  end
end

RSpec.describe OllamaAgent::Tools::AskHuman do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("ask_human")
    end

    it "is low risk" do
      expect(tool.risk_level).to eq(:low)
    end

    it "is read_only safe" do
      expect(tool.read_only_safe).to be(true)
    end
  end
end

RSpec.describe OllamaAgent::Tools::SetContext do
  let(:tool) { described_class.new }
  let(:context_manager) { double("context_manager") }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("set_context")
    end

    it "is read_only safe" do
      expect(tool.read_only_safe).to be(true)
    end
  end

  describe "#call" do
    it "sets a context value" do
      expect(context_manager).to receive(:set).with("task", "refactor")
      result = tool.call({ "key" => "task", "value" => "refactor" }, context: { context_manager: context_manager })
      expect(result).to match(/Context set/)
    end

    it "returns error without context_manager" do
      result = tool.call({ "key" => "x", "value" => "y" }, context: {})
      expect(result).to match(/no context manager/)
    end
  end
end

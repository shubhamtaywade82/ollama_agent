# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::Memory::Manager do
  subject(:manager) { described_class.new(root: tmp_root, session_id: "test_session") }

  let(:tmp_root) { Dir.mktmpdir("ollama_agent_memory_spec") }

  after { FileUtils.rm_rf(tmp_root) }

  describe "#record_tool_call" do
    it "adds an entry to short-term memory" do
      manager.record_tool_call("read_file", { path: "lib/x.rb" }, "content")
      expect(manager.short_term.size).to be >= 1
    end

    it "records both the call and the result" do
      manager.record_tool_call("read_file", { path: "lib/x.rb" }, "content")
      types = manager.short_term.entries.map(&:type)
      expect(types).to include(:tool_call)
      expect(types).to include(:tool_result)
    end
  end

  describe "#remember and #recall (session tier)" do
    it "stores and retrieves a value" do
      manager.remember("preferred_lang", "Ruby", tier: :session)
      expect(manager.recall("preferred_lang", tier: :session)).to eq("Ruby")
    end
  end

  describe "#remember and #recall (long_term tier)" do
    it "persists and retrieves a value" do
      manager.remember("project_lang", "Ruby", tier: :long_term)
      expect(manager.recall("project_lang", tier: :long_term)).to eq("Ruby")
    end
  end

  describe "#forget" do
    it "removes a session key" do
      manager.remember("key", "val", tier: :session)
      manager.forget("key", tier: :session)
      expect(manager.recall("key", tier: :session)).to be_nil
    end
  end

  describe "#list" do
    it "returns all session entries" do
      manager.remember("a", "1", tier: :session)
      manager.remember("b", "2", tier: :session)
      result = manager.list(tier: :session)
      expect(result).to include("a" => "1", "b" => "2")
    end
  end

  describe "#flush_short_term!" do
    it "clears short-term memory" do
      manager.record_tool_call("read_file", {}, "x")
      manager.flush_short_term!
      expect(manager.short_term.size).to eq(0)
    end
  end

  describe "#summary" do
    it "returns a hash with tier information" do
      s = manager.summary
      expect(s).to include(:short_term_entries, :session_keys, :long_term_namespaces)
    end
  end

  describe "goal tracking" do
    it "tracks active goals" do
      manager.set_goal("Fix authentication bug")
      expect(manager.active_goals.map { |g| g[:description] }).to include("Fix authentication bug")
    end

    it "completes a goal" do
      manager.set_goal("Fix bug")
      manager.complete_goal("Fix bug")
      expect(manager.active_goals).to be_empty
    end
  end
end

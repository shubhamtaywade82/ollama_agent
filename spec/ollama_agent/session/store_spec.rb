# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require_relative "../../../lib/ollama_agent/session/session"
require_relative "../../../lib/ollama_agent/session/store"

RSpec.describe OllamaAgent::Session::Store do
  let(:root) { Dir.mktmpdir }

  after { FileUtils.remove_entry(root) }

  describe ".save and .load" do
    it "saves a message and loads it back" do
      described_class.save(session_id: "s1", root: root, message: { role: "user", content: "hello" })
      messages = described_class.load(session_id: "s1", root: root)
      expect(messages.size).to eq(1)
      expect(messages.first["role"]).to eq("user")
      expect(messages.first["content"]).to eq("hello")
    end

    it "appends messages (crash-safe: one line per call)" do
      described_class.save(session_id: "s2", root: root, message: { role: "user", content: "a" })
      described_class.save(session_id: "s2", root: root, message: { role: "assistant", content: "b" })
      messages = described_class.load(session_id: "s2", root: root)
      expect(messages.size).to eq(2)
    end

    it "returns empty array for unknown session" do
      expect(described_class.load(session_id: "nope", root: root)).to eq([])
    end
  end

  describe ".list" do
    it "lists sessions for a root, newest first" do
      described_class.save(session_id: "alpha", root: root, message: { role: "user", content: "x" })
      sleep 0.01 # ensure different mtime
      described_class.save(session_id: "beta", root: root, message: { role: "user", content: "y" })
      list = described_class.list(root: root)
      expect(list.map { |s| s[:session_id] }).to eq(%w[beta alpha])
    end

    it "returns empty array when no sessions exist" do
      expect(described_class.list(root: root)).to eq([])
    end
  end

  describe ".resume" do
    it "returns messages ready for Agent seeding" do
      described_class.save(session_id: "r1", root: root, message: { role: "user", content: "task" })
      described_class.save(session_id: "r1", root: root, message: { role: "assistant", content: "done" })
      messages = described_class.resume(session_id: "r1", root: root)
      expect(messages.size).to eq(2)
      expect(messages.first).to be_a(Hash)
      expect(messages.first["role"]).to eq("user")
    end

    it "returns empty array when session does not exist" do
      expect(described_class.resume(session_id: "gone", root: root)).to eq([])
    end
  end

  describe ".sessions_dir" do
    it "returns path under .ollama_agent/sessions/" do
      expect(described_class.sessions_dir(root)).to end_with(".ollama_agent/sessions")
    end
  end
end

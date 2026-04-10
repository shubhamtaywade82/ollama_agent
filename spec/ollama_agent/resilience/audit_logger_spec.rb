# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/ollama_agent/resilience/audit_logger"
require_relative "../../../lib/ollama_agent/streaming/hooks"

RSpec.describe OllamaAgent::Resilience::AuditLogger do
  let(:log_dir) { Dir.mktmpdir }
  let(:hooks)   { OllamaAgent::Streaming::Hooks.new }

  after { FileUtils.remove_entry(log_dir) }

  def attach_and_emit(event, payload)
    logger = described_class.new(log_dir: log_dir, hooks: hooks)
    logger.attach
    hooks.emit(event, payload)
  end

  def read_log_lines
    files = Dir.glob(File.join(log_dir, "*.ndjson"))
    return [] if files.empty?

    File.read(files.first).lines.map { |l| JSON.parse(l) }
  end

  describe "#attach" do
    it "writes a tool_call entry to the log on on_tool_call" do
      attach_and_emit(:on_tool_call, { name: "read_file", args: { "path" => "x.rb" }, turn: 1 })
      lines = read_log_lines
      expect(lines.size).to eq(1)
      expect(lines.first["event"]).to eq("tool_call")
      expect(lines.first["name"]).to  eq("read_file")
    end

    it "writes a tool_result entry on on_tool_result" do
      attach_and_emit(:on_tool_result, { name: "read_file", result: "content here", turn: 1 })
      lines = read_log_lines
      expect(lines.first["event"]).to eq("tool_result")
    end

    it "writes an agent_complete entry on on_complete" do
      attach_and_emit(:on_complete, { messages: [], turns: 3 })
      lines = read_log_lines
      expect(lines.first["event"]).to eq("agent_complete")
      expect(lines.first["turns"]).to eq(3)
    end

    it "writes an http_retry entry on on_retry" do
      attach_and_emit(:on_retry, { error: Timeout::Error.new("t"), attempt: 1, delay_ms: 2000 })
      lines = read_log_lines
      expect(lines.first["event"]).to eq("http_retry")
      expect(lines.first["attempt"]).to eq(1)
    end

    it "does not raise when the log dir is not writable" do
      logger = described_class.new(log_dir: "/proc/nonexistent_dir_that_cannot_exist", hooks: hooks)
      expect { logger.attach }.not_to raise_error
      hooks.emit(:on_tool_call, { name: "t", args: {}, turn: 1 })
    end

    it "creates the log directory automatically if missing" do
      missing = File.join(log_dir, "nested", "logs")
      logger = described_class.new(log_dir: missing, hooks: hooks)
      logger.attach
      hooks.emit(:on_complete, { messages: [], turns: 1 })
      expect(Dir.exist?(missing)).to be true
    end
  end
end

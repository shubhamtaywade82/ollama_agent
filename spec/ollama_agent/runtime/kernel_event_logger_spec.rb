# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"

RSpec.describe OllamaAgent::Runtime::KernelEventLogger do
  it "emits one JSON log line per emit" do
    io = StringIO.new
    logger = Logger.new(io, progname: "test")
    logger.formatter = proc { |_s, _d, _p, msg| "#{msg}\n" }
    described_class.new(logger: logger).emit(:on_saga_start, manifest_id: "m1", kind: "atomic_write", scopes: %w[a])
    line = io.string.lines.last
    h = JSON.parse(line)
    expect(h["event"]).to eq("on_saga_start")
    expect(h["manifest_id"]).to eq("m1")
    expect(h["kind"]).to eq("atomic_write")
    expect(h["scopes"]).to eq(%w[a])
  end

  it "forwards mutation outcomes to RollbackSignals" do
    io = StringIO.new
    logger = Logger.new(io)
    logger.formatter = proc { |_s, _d, _p, msg| "#{msg}\n" }
    rs = OllamaAgent::Runtime::RollbackSignals.new(thresholds: { mutation_failure_rate: 0.5 })
    rs.tick(epoch: 1)
    log = described_class.new(logger: logger, rollback_signals: rs)
    log.emit(:on_kernel_pipeline_complete, manifest_id: "x", result: :ok)
    log.emit(:on_kernel_pipeline_complete, manifest_id: "x", result: :error)
    expect(rs.should_rollback?[:trigger]).to be(true)
  end
end

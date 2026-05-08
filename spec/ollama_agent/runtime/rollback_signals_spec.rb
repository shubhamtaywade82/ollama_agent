# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::RollbackSignals do
  it "detects replay determinism threshold" do
    rs = described_class.new(thresholds: { replay_determinism_violations_per_min: 1 })
    rs.tick(epoch: 10)
    rs.record(event: :replay_determinism_violation, payload: { epoch: 10 })
    got = rs.should_rollback?
    expect(got[:trigger]).to be(true)
    expect(got[:reasons].join(" ")).to include("replay_determinism")
  end

  it "detects recovery duplicate threshold" do
    rs = described_class.new(thresholds: { recovery_duplicates_per_min: 1 })
    rs.tick(epoch: 1)
    rs.record(event: :recovery_duplicate, payload: { epoch: 1 })
    expect(rs.should_rollback?[:trigger]).to be(true)
  end

  it "detects validator integrity threshold" do
    rs = described_class.new(thresholds: { validator_integrity_mismatches_per_min: 1 })
    rs.tick(epoch: 2)
    rs.record(event: :validator_integrity_mismatch, payload: { epoch: 2 })
    expect(rs.should_rollback?[:trigger]).to be(true)
  end

  it "detects mutation failure rate threshold" do
    rs = described_class.new(thresholds: { mutation_failure_rate: 0.2 })
    rs.tick(epoch: 5)
    rs.record(event: :mutation_failure, payload: { epoch: 5 })
    9.times { rs.record(event: :mutation_success, payload: { epoch: 5 }) }
    expect(rs.should_rollback?[:trigger]).to be(false)

    rs2 = described_class.new(thresholds: { mutation_failure_rate: 0.3 })
    rs2.tick(epoch: 6)
    2.times { rs2.record(event: :mutation_failure, payload: { epoch: 6 }) }
    3.times { rs2.record(event: :mutation_success, payload: { epoch: 6 }) }
    expect(rs2.should_rollback?[:trigger]).to be(true)
  end

  it "evicts rows outside the 60-tick window when tick advances" do
    rs = described_class.new(thresholds: { replay_determinism_violations_per_min: 1 })
    rs.tick(epoch: 0)
    rs.record(event: :replay_determinism_violation, payload: { epoch: 0 })
    rs.tick(epoch: 100)
    expect(rs.should_rollback?[:trigger]).to be(false)
  end
end

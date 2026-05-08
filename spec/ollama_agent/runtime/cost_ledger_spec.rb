# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::Runtime::CostLedger do
  it "records rows and reports total_for_manifest" do
    Dir.mktmpdir("cost-ledger-manifest") do |tmp|
      reg = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: tmp)
      reg.runtime
      ledger = described_class.new(db_registry: reg)

      ledger.record(
        manifest_id: "m-a",
        model: "claude-test",
        input_tokens: 100,
        output_tokens: 50,
        cost_usd: 0.01,
        current_epoch: 100
      )
      ledger.record(
        manifest_id: "m-a",
        model: "claude-test",
        input_tokens: 10,
        output_tokens: 5,
        cost_usd: 0.02,
        current_epoch: 150
      )

      expect(ledger.total_for_manifest(manifest_id: "m-a")).to eq(0.03)
    end
  end

  it "sums totals in a created_at_epoch window" do
    Dir.mktmpdir("cost-ledger-window") do |tmp|
      reg = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: tmp)
      reg.runtime
      ledger = described_class.new(db_registry: reg)

      ledger.record(
        manifest_id: "m-a",
        model: "claude-test",
        input_tokens: 1,
        output_tokens: 1,
        cost_usd: 0.01,
        current_epoch: 100
      )
      ledger.record(
        manifest_id: "m-b",
        model: "claude-test",
        input_tokens: 1,
        output_tokens: 1,
        cost_usd: 0.50,
        current_epoch: 200
      )

      expect(ledger.total_in_window(since_epoch: 0, until_epoch: 120)).to eq(0.01)
      expect(ledger.total_in_window(since_epoch: 120, until_epoch: 200)).to eq(0.50)
    end
  end
end

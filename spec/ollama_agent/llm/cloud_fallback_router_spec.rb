# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::LLM::CloudFallbackRouter do
  let(:packet) do
    OllamaAgent::State::ReentryPacket.new(
      reason: "r",
      workspace_fingerprint: "f",
      changed_files: [],
      summary: "{}"
    )
  end

  let(:builder) { instance_double(Object) }
  let(:client) { instance_double(OllamaAgent::LLM::AnthropicClient) }

  it "halts on max escalation depth" do
    allow(client).to receive(:chat)
    router = described_class.new(
      anthropic_client: client,
      reentry_packet_builder: builder,
      max_escalation_depth: 1
    )
    out = router.escalate(packet: packet, depth: 1, accumulated_cost_usd: 0.0, started_at: 0)
    expect(out[:result]).to eq(:depth_limit_exceeded)
    expect(out[:halted_reason]).to eq("max_escalation_depth")
    expect(client).not_to have_received(:chat)
  end

  it "halts when the cost cap is already reached" do
    allow(client).to receive(:chat)
    router = described_class.new(
      anthropic_client: client,
      reentry_packet_builder: builder,
      cost_cap_usd: 1.0
    )
    out = router.escalate(packet: packet, depth: 0, accumulated_cost_usd: 1.0, started_at: 0)
    expect(out[:result]).to eq(:cost_cap_exceeded)
    expect(out[:halted_reason]).to eq("cost_cap")
  end

  it "halts when the time cap elapses" do
    allow(client).to receive(:chat)
    clock = proc { 700 }
    router = described_class.new(
      anthropic_client: client,
      reentry_packet_builder: builder,
      time_cap_seconds: 600,
      clock_provider: clock
    )
    out = router.escalate(packet: packet, depth: 0, accumulated_cost_usd: 0.0, started_at: 0)
    expect(out[:result]).to eq(:time_cap_exceeded)
    expect(out[:halted_reason]).to eq("time_cap")
  end

  it "delegates to Anthropic and accumulates cost from usage" do
    allow(client).to receive(:chat).and_return(
      content: "ok",
      stop_reason: "end_turn",
      usage: { input_tokens: 1_000_000, output_tokens: 0 }
    )
    router = described_class.new(
      anthropic_client: client,
      reentry_packet_builder: builder,
      max_escalation_depth: 2,
      cost_cap_usd: 100.0,
      time_cap_seconds: 600,
      clock_provider: -> { 10 }
    )
    out = router.escalate(packet: packet, depth: 0, accumulated_cost_usd: 0.0, started_at: 0)
    expect(out[:result]).to eq("ok")
    expect(out[:depth]).to eq(1)
    expect(out[:halted_reason]).to be_nil
    expect(out[:cost_usd]).to eq(described_class::OPUS_47_INPUT_USD_PER_MILLION)
  end

  it "persists cost to the ledger and ignores stale accumulated_cost_usd when a ledger is configured" do
    Dir.mktmpdir("cloud-router-ledger") do |tmp|
      reg = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: tmp)
      reg.runtime
      ledger = OllamaAgent::Runtime::CostLedger.new(db_registry: reg)
      allow(client).to receive_messages(
        chat: {
          content: "ok",
          stop_reason: "end_turn",
          usage: { input_tokens: 1_000_000, output_tokens: 0 }
        },
        model: "claude-test"
      )

      router = described_class.new(
        anthropic_client: client,
        reentry_packet_builder: builder,
        cost_ledger: ledger,
        max_escalation_depth: 2,
        cost_cap_usd: 100.0,
        time_cap_seconds: 600,
        clock_provider: -> { 10 }
      )
      out = router.escalate(packet: packet, depth: 0, accumulated_cost_usd: 999.0, started_at: 0, manifest_id: "m1")
      expect(out[:halted_reason]).to be_nil
      expect(ledger.total_for_manifest(manifest_id: "m1")).to eq(out[:cost_usd])
    end
  end

  it "halts on persisted cost when the ledger already exceeds the cap" do
    Dir.mktmpdir("cloud-router-ledger-cap") do |tmp|
      reg = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: tmp)
      reg.runtime
      ledger = OllamaAgent::Runtime::CostLedger.new(db_registry: reg)
      ledger.record(
        manifest_id: "m1",
        model: "x",
        input_tokens: 0,
        output_tokens: 0,
        cost_usd: 10.0,
        current_epoch: 1
      )
      allow(client).to receive(:chat)

      router = described_class.new(
        anthropic_client: client,
        reentry_packet_builder: builder,
        cost_ledger: ledger,
        cost_cap_usd: 5.0
      )
      out = router.escalate(packet: packet, depth: 0, accumulated_cost_usd: 0.0, started_at: 0, manifest_id: "m1")
      expect(out[:result]).to eq(:cost_cap_exceeded)
      expect(client).not_to have_received(:chat)
    end
  end
end

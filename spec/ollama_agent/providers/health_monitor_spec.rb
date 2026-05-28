# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/errors"
require "ollama_agent/providers/health_monitor"

RSpec.describe OllamaAgent::Providers::HealthMonitor do
  def make_cred(id, provider = "openai")
    instance_double(
      OllamaAgent::Providers::Credential,
      id: id, provider: provider
    )
  end

  subject(:monitor) { described_class.new(max_events: 10) }

  describe "#record_success" do
    it "stores a success event" do
      cred = make_cred("k1")
      monitor.record_success(cred, latency_ms: 120)
      events = monitor.recent_events
      expect(events.last.kind).to eq(:success)
      expect(events.last.latency_ms).to eq(120)
    end
  end

  describe "#record_failure" do
    it "stores a failure event with error class" do
      cred = make_cred("k1")
      monitor.record_failure(cred, OllamaAgent::RateLimitError.new("429"))
      events = monitor.recent_events
      expect(events.last.kind).to eq(:failure)
      expect(events.last.error_class).to eq("OllamaAgent::RateLimitError")
    end
  end

  describe "#routing_decisions" do
    it "formats events as human-readable strings" do
      cred = make_cred("k1")
      monitor.record_success(cred, latency_ms: 200)
      monitor.record_failure(cred, OllamaAgent::QuotaExhaustedError.new("quota"))
      decisions = monitor.routing_decisions
      expect(decisions.first).to match(/success/)
      expect(decisions.last).to match(/QuotaExhaustedError/)
    end
  end

  describe "#recent_failure_rate" do
    it "returns 0.0 with no events" do
      expect(monitor.recent_failure_rate).to eq(0.0)
    end

    it "calculates correct failure ratio" do
      cred = make_cred("k1")
      2.times { monitor.record_success(cred) }
      2.times { monitor.record_failure(cred, OllamaAgent::RateLimitError.new) }
      expect(monitor.recent_failure_rate).to be_within(0.01).of(0.5)
    end
  end

  describe "max_events cap" do
    it "does not grow beyond max_events" do
      cred = make_cred("k1")
      15.times { monitor.record_success(cred) }
      expect(monitor.recent_events.size).to eq(10)
    end
  end
end

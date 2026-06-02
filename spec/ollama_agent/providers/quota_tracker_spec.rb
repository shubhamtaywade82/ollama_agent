# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/providers/quota_tracker"

RSpec.describe OllamaAgent::Providers::QuotaTracker do
  subject(:tracker) { described_class.new(limits: limits) }

  let(:limits) { { rpm: 10, tpm: 1000, daily_tokens: 5000, daily_requests: 100 } }

  describe "#record" do
    it "accumulates daily tokens from usage hash" do
      tracker.record({ total_tokens: 200 })
      tracker.record({ total_tokens: 300 })
      expect(tracker.summary[:daily_tokens]).to eq(500)
    end

    it "accumulates daily request count" do
      3.times { tracker.record({ total_tokens: 10 }) }
      expect(tracker.summary[:daily_requests]).to eq(3)
    end

    it "accepts string keys" do
      tracker.record({ "total_tokens" => 100 })
      expect(tracker.summary[:daily_tokens]).to eq(100)
    end

    it "handles nil usage gracefully" do
      expect { tracker.record(nil) }.not_to raise_error
    end
  end

  describe "#exhausted?" do
    it "returns false when below limits" do
      tracker.record({ total_tokens: 100 })
      expect(tracker.exhausted?).to be false
    end

    it "returns true when daily token limit is reached" do
      tracker.record({ total_tokens: 5000 })
      expect(tracker.exhausted?).to be true
    end

    it "returns true when daily request limit is reached" do
      100.times { tracker.record({ total_tokens: 1 }) }
      expect(tracker.exhausted?).to be true
    end

    it "returns false with no limits configured" do
      t = described_class.new(limits: {})
      expect(t.exhausted?).to be false
    end
  end

  describe "#near_exhaustion?" do
    it "returns false when under 90% of daily token limit" do
      tracker.record({ total_tokens: 4400 })
      expect(tracker.near_exhaustion?).to be false
    end

    it "returns true when >= 90% of daily token limit" do
      tracker.record({ total_tokens: 4500 })
      expect(tracker.near_exhaustion?).to be true
    end
  end

  describe "#daily_utilisation" do
    it "returns fraction of daily token limit used" do
      tracker.record({ total_tokens: 2500 })
      expect(tracker.daily_utilisation).to be_within(0.001).of(0.5)
    end

    it "returns 0.0 when no daily limit configured" do
      t = described_class.new(limits: {})
      expect(t.daily_utilisation).to eq(0.0)
    end
  end

  describe "#summary" do
    it "returns a complete hash with all quota fields" do
      tracker.record({ total_tokens: 100 })
      s = tracker.summary
      expect(s.keys).to include(
        :daily_tokens, :daily_tokens_limit, :daily_requests,
        :rpm, :rpm_limit, :tpm, :tpm_limit, :daily_pct, :resets_at
      )
    end
  end
end

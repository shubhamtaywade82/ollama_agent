# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/errors"
require "ollama_agent/providers/credential"

RSpec.describe OllamaAgent::Providers::Credential do
  subject(:cred) do
    described_class.new(
      id: "openai-1", provider: "openai",
      api_key: "sk-test",
      weight: 2,
      limits: { daily_tokens: 1000 }
    )
  end

  describe "#available?" do
    it "is true for a fresh credential" do
      expect(cred.available?).to be true
    end

    it "is false when permanently disabled" do
      cred.mark_failure!(OllamaAgent::AuthenticationError.new("401"))
      expect(cred.available?).to be false
    end

    it "is false when cooling down" do
      cred.mark_failure!(OllamaAgent::RateLimitError.new("429"))
      expect(cred.available?).to be false
    end

    it "is false when quota is exhausted" do
      allow(cred.quota_tracker).to receive(:exhausted?).and_return(true)
      expect(cred.available?).to be false
    end
  end

  describe "#mark_failure!" do
    it "permanently disables on AuthenticationError" do
      cred.mark_failure!(OllamaAgent::AuthenticationError.new("401"))
      expect(cred.status_summary[:disabled]).to be true
    end

    it "applies a 3600s cooldown for QuotaExhaustedError" do
      cred.mark_failure!(OllamaAgent::QuotaExhaustedError.new("quota"))
      expect(cred.cooldown_remaining).to be_within(5).of(3600)
    end

    it "applies a 60s cooldown for RateLimitError" do
      cred.mark_failure!(OllamaAgent::RateLimitError.new("429"))
      expect(cred.cooldown_remaining).to be_within(5).of(60)
    end

    it "applies a 15s cooldown for TemporaryProviderError" do
      cred.mark_failure!(OllamaAgent::TemporaryProviderError.new("500"))
      expect(cred.cooldown_remaining).to be_within(5).of(15)
    end

    it "applies default cooldown for unknown errors" do
      cred.mark_failure!(StandardError.new("unknown"))
      expect(cred.cooldown_remaining).to be_within(5).of(30)
    end
  end

  describe "#mark_success!" do
    it "resets failures and cooldown" do
      cred.mark_failure!(OllamaAgent::RateLimitError.new("429"))
      cred.mark_success!
      expect(cred.available?).to be true
      expect(cred.cooldown_remaining).to eq(0)
    end

    it "records usage via quota_tracker" do
      usage = { total_tokens: 500 }
      expect(cred.quota_tracker).to receive(:record).with(usage)
      cred.mark_success!(usage: usage)
    end
  end

  describe "#status_summary" do
    it "returns a complete status hash" do
      s = cred.status_summary
      expect(s.keys).to include(
        :id, :provider, :name, :available, :disabled,
        :cooling_down, :failures, :near_exhaustion, :quota
      )
    end

    it "reflects near_exhaustion from quota_tracker" do
      allow(cred.quota_tracker).to receive(:near_exhaustion?).and_return(true)
      expect(cred.status_summary[:near_exhaustion]).to be true
    end
  end

  describe "#near_exhaustion?" do
    it "delegates to quota_tracker" do
      allow(cred.quota_tracker).to receive(:near_exhaustion?).and_return(true)
      expect(cred.near_exhaustion?).to be true
    end
  end
end

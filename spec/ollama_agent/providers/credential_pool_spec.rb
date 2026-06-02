# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/errors"
require "ollama_agent/providers/credential_pool"

RSpec.describe OllamaAgent::Providers::CredentialPool do
  def make_cred(id, available: true, weight: 1)
    instance_double(
      OllamaAgent::Providers::Credential,
      id: id,
      weight: weight,
      available?: available,
      near_exhaustion?: false,
      status_summary: { id: id, provider: "openai" },
      quota_tracker: instance_double(OllamaAgent::Providers::QuotaTracker, summary: {})
    )
  end

  let(:cred_a) { make_cred("a", weight: 2) }
  let(:cred_b) { make_cred("b", weight: 1) }
  let(:pool)   { described_class.new(credentials: [cred_a, cred_b]) }

  describe "#next_credential" do
    it "returns an available credential" do
      expect([cred_a, cred_b]).to include(pool.next_credential)
    end

    it "raises NoAvailableCredentialError when all credentials unavailable" do
      unavailable_cred = make_cred("x", available: false)
      p = described_class.new(credentials: [unavailable_cred])
      expect { p.next_credential }.to raise_error(OllamaAgent::NoAvailableCredentialError)
    end

    it "respects weight — higher weight credential appears more often in weighted array" do
      selections = 30.times.map { pool.next_credential }
      a_count = selections.count { |c| c == cred_a }
      b_count = selections.count { |c| c == cred_b }
      # weight 2:1 ratio — a should appear roughly twice as often
      expect(a_count).to be > b_count
    end
  end

  describe "#any_available?" do
    it "returns true when at least one credential is available" do
      expect(pool.any_available?).to be true
    end

    it "returns false when no credentials are available" do
      p = described_class.new(credentials: [make_cred("x", available: false)])
      expect(p.any_available?).to be false
    end
  end

  describe "#near_exhaustion_ids" do
    it "returns ids of near-exhaustion credentials" do
      near = make_cred("near")
      allow(near).to receive(:near_exhaustion?).and_return(true)
      p = described_class.new(credentials: [near, cred_a])
      expect(p.near_exhaustion_ids).to eq(["near"])
    end
  end

  describe "#all_status" do
    it "returns an array of status hashes" do
      statuses = pool.all_status
      expect(statuses.map { |s| s[:id] }).to match_array(%w[a b])
    end
  end

  describe "#size" do
    it "returns the total number of credentials" do
      expect(pool.size).to eq(2)
    end
  end
end

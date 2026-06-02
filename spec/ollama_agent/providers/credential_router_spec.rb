# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/errors"
require "ollama_agent/providers/credential_router"

RSpec.describe OllamaAgent::Providers::CredentialRouter do
  def make_cred(id, available: true)
    cred = instance_double(
      OllamaAgent::Providers::Credential,
      id: id, provider: "openai",
      available?: available,
      near_exhaustion?: false
    )
    allow(cred).to receive(:mark_success!)
    allow(cred).to receive(:mark_failure!)
    cred
  end

  def make_pool(creds)
    pool = instance_double(OllamaAgent::Providers::CredentialPool)
    call_count = 0
    allow(pool).to receive(:next_credential) do
      raise OllamaAgent::NoAvailableCredentialError, "pool empty" if creds.empty?

      creds[call_count % creds.size].tap { call_count += 1 }
    end
    allow(pool).to receive_messages(any_available?: creds.any?(&:available?), all_status: [], aggregate_usage: {},
                                    near_exhaustion_ids: [])
    pool
  end

  let(:fake_response) do
    instance_double(OllamaAgent::Providers::Base::Response, usage: { total_tokens: 100 })
  end

  let(:monitor) { instance_double(OllamaAgent::Providers::HealthMonitor) }

  before do
    allow(monitor).to receive(:record_success)
    allow(monitor).to receive(:record_failure)
    allow(monitor).to receive(:record_switch)
    allow(monitor).to receive(:routing_decisions).and_return([])
  end

  describe "#chat — success path" do
    it "returns the provider response and marks credential success" do
      cred     = make_cred("k1")
      provider = instance_double(OllamaAgent::Providers::Base)
      allow(provider).to receive(:chat).and_return(fake_response)

      pool   = make_pool([cred])
      router = described_class.new(pool: pool, provider_builder: ->(_c) { provider }, health_monitor: monitor)

      response = router.chat(messages: [], model: "gpt-4o")
      expect(response).to eq(fake_response)
      expect(cred).to have_received(:mark_success!)
    end
  end

  describe "#chat — failover on RateLimitError" do
    it "retries with next credential after rate limit" do
      cred_a   = make_cred("a")
      cred_b   = make_cred("b")

      provider_a = instance_double(OllamaAgent::Providers::Base)
      provider_b = instance_double(OllamaAgent::Providers::Base)

      allow(provider_a).to receive(:chat).and_raise(OllamaAgent::RateLimitError, "429")
      allow(provider_b).to receive(:chat).and_return(fake_response)

      providers_map = { "a" => provider_a, "b" => provider_b }
      pool   = make_pool([cred_a, cred_b])
      router = described_class.new(
        pool: pool,
        provider_builder: ->(c) { providers_map[c.id] },
        health_monitor: monitor
      )

      response = router.chat(messages: [], model: "gpt-4o")
      expect(response).to eq(fake_response)
      expect(cred_a).to have_received(:mark_failure!)
    end
  end

  describe "#chat — AuthenticationError bubbles immediately" do
    it "raises AuthenticationError without retrying" do
      cred     = make_cred("k1")
      provider = instance_double(OllamaAgent::Providers::Base)
      allow(provider).to receive(:chat).and_raise(OllamaAgent::AuthenticationError, "401")

      pool   = make_pool([cred])
      router = described_class.new(pool: pool, provider_builder: ->(_c) { provider }, health_monitor: monitor)

      expect { router.chat(messages: [], model: "gpt-4o") }
        .to raise_error(OllamaAgent::AuthenticationError)
      expect(cred).to have_received(:mark_failure!)
    end
  end

  describe "#chat — exhausts max attempts" do
    it "raises NoAvailableCredentialError after MAX_ATTEMPTS" do
      cred     = make_cred("k1")
      provider = instance_double(OllamaAgent::Providers::Base)
      allow(provider).to receive(:chat).and_raise(OllamaAgent::RateLimitError, "429")

      pool   = make_pool([cred])
      router = described_class.new(pool: pool, provider_builder: ->(_c) { provider }, health_monitor: monitor)

      expect { router.chat(messages: [], model: "gpt-4o") }
        .to raise_error(OllamaAgent::NoAvailableCredentialError)
    end
  end

  describe "#available?" do
    it "delegates to pool#any_available?" do
      pool   = make_pool([make_cred("k1")])
      router = described_class.new(pool: pool, provider_builder: ->(_c) {}, health_monitor: monitor)
      expect(router.available?).to be true
    end
  end
end

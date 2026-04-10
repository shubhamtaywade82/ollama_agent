# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ollama_agent/resilience/retry_policy"

RSpec.describe OllamaAgent::Resilience::RetryPolicy do
  subject(:policy) { described_class.new(max_attempts: 3, base_delay: 2.0) }

  describe "#retryable_http_error?" do
    it "returns false for HTTP 400" do
      err = StandardError.new("HTTP 400: bad request")
      expect(policy.retryable_http_error?(err)).to be false
    end

    it "returns true for HTTP 429 without hard limit wording" do
      err = StandardError.new("HTTP 429: rate limit")
      expect(policy.retryable_http_error?(err)).to be true
    end

    it "returns false for HTTP 429 with weekly usage limit" do
      err = StandardError.new("HTTP 429: weekly usage limit exceeded")
      expect(policy.retryable_http_error?(err)).to be false
    end

    it "returns true for HTTP 503" do
      err = StandardError.new("HTTP 503: unavailable")
      expect(policy.retryable_http_error?(err)).to be true
    end
  end

  describe "#backoff" do
    it "increases with attempt" do
      expect(policy.backoff(1)).to be <= policy.backoff(2)
    end
  end
end

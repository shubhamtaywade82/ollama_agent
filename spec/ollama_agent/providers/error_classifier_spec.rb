# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/errors"
require "ollama_agent/providers/error_classifier"

RSpec.describe OllamaAgent::Providers::ErrorClassifier do
  describe ".classify" do
    subject(:classify) { described_class.classify(error, http_status: status) }

    let(:status) { nil }

    context "with HTTP 401" do
      let(:error)  { OllamaAgent::Error.new("OpenAI auth failed (401): invalid key") }
      let(:status) { 401 }

      it { is_expected.to be_a(OllamaAgent::AuthenticationError) }
    end

    context "with HTTP 403" do
      let(:error)  { OllamaAgent::Error.new("forbidden") }
      let(:status) { 403 }

      it { is_expected.to be_a(OllamaAgent::AuthenticationError) }
    end

    context "with HTTP 402" do
      let(:error)  { OllamaAgent::Error.new("payment required") }
      let(:status) { 402 }

      it { is_expected.to be_a(OllamaAgent::QuotaExhaustedError) }
    end

    context "with HTTP 429 and plain rate-limit message" do
      let(:error)  { OllamaAgent::Error.new("rate limited") }
      let(:status) { 429 }

      it { is_expected.to be_a(OllamaAgent::RateLimitError) }
    end

    context "with HTTP 429 and quota exhaustion phrasing" do
      let(:error)  { OllamaAgent::Error.new("you have exceeded your current quota, please check your plan") }
      let(:status) { 429 }

      it { is_expected.to be_a(OllamaAgent::QuotaExhaustedError) }
    end

    context "with HTTP 429 and weekly usage limit" do
      let(:error)  { OllamaAgent::Error.new("weekly usage limit reached") }
      let(:status) { 429 }

      it { is_expected.to be_a(OllamaAgent::QuotaExhaustedError) }
    end

    context "with HTTP 500" do
      let(:error)  { OllamaAgent::Error.new("internal server error") }
      let(:status) { 500 }

      it { is_expected.to be_a(OllamaAgent::TemporaryProviderError) }
    end

    context "with Timeout::Error" do
      let(:error) { Timeout::Error.new("execution expired") }

      it { is_expected.to be_a(OllamaAgent::TemporaryProviderError) }
    end

    context "with Errno::ECONNREFUSED" do
      let(:error) { Errno::ECONNREFUSED.new }

      it { is_expected.to be_a(OllamaAgent::TemporaryProviderError) }
    end

    context "with unknown error" do
      let(:error) { RuntimeError.new("something weird") }

      it "passes through as-is" do
        expect(classify).to be_a(RuntimeError)
      end
    end

    context "extracting status from error message" do
      let(:error) { OllamaAgent::Error.new("HTTP 429: too many requests") }

      it { is_expected.to be_a(OllamaAgent::RateLimitError) }
    end
  end

  describe ".permanently_disabling?" do
    it "returns true for AuthenticationError" do
      expect(described_class.permanently_disabling?(OllamaAgent::AuthenticationError.new)).to be true
    end

    it "returns false for other errors" do
      expect(described_class.permanently_disabling?(OllamaAgent::RateLimitError.new)).to be false
    end
  end

  describe ".retryable_with_other_credential?" do
    [
      OllamaAgent::RateLimitError,
      OllamaAgent::QuotaExhaustedError,
      OllamaAgent::TemporaryProviderError
    ].each do |error_class|
      it "returns true for #{error_class}" do
        expect(described_class.retryable_with_other_credential?(error_class.new)).to be true
      end
    end

    it "returns false for AuthenticationError" do
      expect(described_class.retryable_with_other_credential?(OllamaAgent::AuthenticationError.new)).to be false
    end
  end
end

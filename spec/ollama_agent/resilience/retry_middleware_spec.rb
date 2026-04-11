# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ollama_agent/resilience/retry_middleware"
require_relative "../../../lib/ollama_agent/streaming/hooks"

RSpec.describe OllamaAgent::Resilience::RetryMiddleware do
  let(:hooks) { OllamaAgent::Streaming::Hooks.new }

  # rubocop:disable RSpec/VerifiedDoubles -- generic test doubles; no real Ollama::Client dependency
  def make_client(responses)
    client = double("client")
    allow(client).to receive(:chat).and_invoke(*responses.map do |r|
      r.is_a?(Class) ? ->(**_) { raise r } : ->(**_) { r }
    end)
    client
  end

  def build_http_400_error
    skip "Ollama::HTTPError not defined" unless defined?(Ollama::HTTPError)

    Ollama::HTTPError.new("HTTP 400: bad request")
  end

  describe "#chat" do
    it "passes through when the first call succeeds" do
      response = double("response")
      client   = make_client([response])
      mw       = described_class.new(client: client, max_attempts: 3, hooks: hooks, base_delay: 0)
      expect(mw.chat(messages: [], tools: [], model: "m")).to eq(response)
    end

    it "retries on Timeout::Error and succeeds on the second attempt" do
      response = double("response")
      client   = make_client([Timeout::Error, response])
      mw       = described_class.new(client: client, max_attempts: 3, hooks: hooks, base_delay: 0)
      expect(mw.chat(messages: [], tools: [], model: "m")).to eq(response)
    end

    it "raises after exhausting max_attempts" do
      client = make_client([Timeout::Error, Timeout::Error, Timeout::Error])
      mw     = described_class.new(client: client, max_attempts: 3, hooks: hooks, base_delay: 0)
      expect { mw.chat(messages: [], tools: [], model: "m") }.to raise_error(Timeout::Error)
    end

    it "does not retry non-retryable errors" do
      client = make_client([ArgumentError])
      mw     = described_class.new(client: client, max_attempts: 3, hooks: hooks, base_delay: 0)
      expect { mw.chat(messages: [], tools: [], model: "m") }.to raise_error(ArgumentError)
    end

    it "does not retry Ollama::HTTPError with status 400" do
      err = build_http_400_error
      client = instance_spy(Ollama::Client)
      allow(client).to receive(:chat).and_raise(err)
      mw = described_class.new(client: client, max_attempts: 3, hooks: hooks, base_delay: 0)
      expect { mw.chat(messages: [], tools: [], model: "m") }.to raise_error(err.class, /HTTP 400/)
      expect(client).to have_received(:chat).once
    end

    it "emits on_retry hook on each retry attempt" do
      response = double("response")
      client   = make_client([Timeout::Error, response])
      mw       = described_class.new(client: client, max_attempts: 3, hooks: hooks, base_delay: 0)
      retries  = []
      hooks.on(:on_retry) { |p| retries << p[:attempt] }
      mw.chat(messages: [], tools: [], model: "m")
      expect(retries).to eq([1])
    end

    it "does not retry when max_attempts is 1" do
      client = make_client([Timeout::Error])
      mw     = described_class.new(client: client, max_attempts: 1, hooks: hooks, base_delay: 0)
      expect { mw.chat(messages: [], tools: [], model: "m") }.to raise_error(Timeout::Error)
    end

    it "retries on SocketError if defined" do
      # Mock SocketError if not present
      stub_const("SocketError", Class.new(StandardError)) unless defined?(SocketError)
      response = double("response")
      client   = make_client([SocketError, response])
      mw       = described_class.new(client: client, max_attempts: 3, hooks: hooks, base_delay: 0)
      expect(mw.chat(messages: [], tools: [], model: "m")).to eq(response)
    end

    it "retries on Ollama::Error if defined" do
      # Mock Ollama::Error if not present
      # rubocop:disable RSpec/LeakyConstantDeclaration -- minimal stand-in when gem omits the class
      module Ollama; class Error < StandardError; end; end unless defined?(Ollama::Error)
      # rubocop:enable RSpec/LeakyConstantDeclaration
      response = double("response")
      client   = make_client([Ollama::Error, response])
      mw       = described_class.new(client: client, max_attempts: 3, hooks: hooks, base_delay: 0)
      expect(mw.chat(messages: [], tools: [], model: "m")).to eq(response)
    end
  end

  describe "#list_model_names" do
    it "delegates to the inner client" do
      client = instance_double(Ollama::Client)
      allow(client).to receive(:list_model_names).and_return(%w[m1])
      mw = described_class.new(client: client, max_attempts: 1, hooks: hooks, base_delay: 0)
      expect(mw.list_model_names).to eq(%w[m1])
    end
  end
  # rubocop:enable RSpec/VerifiedDoubles
end

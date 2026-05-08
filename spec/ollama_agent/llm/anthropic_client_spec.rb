# frozen_string_literal: true

require "spec_helper"
require "json"
require "net/http"
require_relative "../../support/anthropic_client_http_stub"

RSpec.describe OllamaAgent::LLM::AnthropicClient do
  let(:api_key) { "sk-test" }
  let(:success_body) do
    {
      "content" => [{ "type" => "text", "text" => "hello" }],
      "stop_reason" => "end_turn",
      "usage" => { "input_tokens" => 10, "output_tokens" => 20 }
    }
  end

  before do
    OllamaAgent::AnthropicClientSpec::HttpStub.instances = []
    OllamaAgent::AnthropicClientSpec::HttpStub.response = instance_double(
      Net::HTTPResponse,
      code: "200",
      body: JSON.generate(success_body)
    )
  end

  it "returns parsed assistant text, stop_reason, and usage" do
    client = described_class.new(api_key: api_key, http_client: OllamaAgent::AnthropicClientSpec::HttpStub)
    out = client.chat(messages: [{ role: "user", content: "hi" }])
    expect(out[:content]).to eq("hello")
    expect(out[:stop_reason]).to eq("end_turn")
    expect(out[:usage]).to eq({ input_tokens: 10, output_tokens: 20 })
  end

  it "raises AnthropicAPIError on non-200 responses" do
    OllamaAgent::AnthropicClientSpec::HttpStub.response = instance_double(
      Net::HTTPResponse,
      code: "500",
      body: "err"
    )
    client = described_class.new(api_key: api_key, http_client: OllamaAgent::AnthropicClientSpec::HttpStub)
    expect do
      client.chat(messages: [{ role: "user", content: "hi" }])
    end.to raise_error(OllamaAgent::AnthropicAPIError, /status=500/)
  end

  it "wraps read timeouts as AnthropicAPIError" do
    timeout_class = Class.new(OllamaAgent::AnthropicClientSpec::HttpStub) do
      def request(_req)
        raise Net::ReadTimeout, "timed out"
      end
    end
    client = described_class.new(api_key: api_key, http_client: timeout_class)
    expect do
      client.chat(messages: [{ role: "user", content: "hi" }])
    end.to raise_error(OllamaAgent::AnthropicAPIError, /timeout/)
  end
end

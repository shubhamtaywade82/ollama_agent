# frozen_string_literal: true

require "spec_helper"
require "json"
require "net/http"

RSpec.describe OllamaAgent::LLM::AnthropicClient do
  let(:api_key) { "sk-test" }
  let(:success_body) do
    {
      "content" => [{ "type" => "text", "text" => "ok" }],
      "stop_reason" => "end_turn",
      "usage" => { "input_tokens" => 1, "output_tokens" => 2 }
    }
  end

  def response_double(code:, body:, retry_after: nil)
    instance_double(Net::HTTPResponse, code: code.to_s, body: body).tap do |d|
      allow(d).to receive(:[]).with("retry-after").and_return(retry_after)
    end
  end

  # rubocop:disable RSpec/ExampleLength
  it "retries on 429 and eventually returns 200" do
    seq = [
      response_double(code: 429, body: "wait"),
      response_double(code: 200, body: JSON.generate(success_body))
    ]
    http_class = Class.new do
      define_singleton_method(:responses) { seq }
      def initialize(*)
        nil
      end

      def use_ssl=(flag)
        flag
      end

      def open_timeout=(seconds)
        seconds
      end

      def read_timeout=(seconds)
        seconds
      end

      def request(_req)
        self.class.responses.shift
      end
    end
    sleeps = []
    client = described_class.new(
      api_key: api_key,
      http_client: http_class,
      sleep: proc { |s| sleeps << s },
      random: Random.new(1)
    )
    out = client.chat(messages: [{ role: "user", content: "hi" }])
    expect(out[:content]).to eq("ok")
    expect(sleeps.size).to eq(1)
  end
  # rubocop:enable RSpec/ExampleLength

  it "honors Retry-After seconds when present" do
    seq = [
      response_double(code: 429, body: "wait", retry_after: "3"),
      response_double(code: 200, body: JSON.generate(success_body))
    ]
    http_class = Class.new do
      define_singleton_method(:responses) { seq }
      def initialize(*)
        nil
      end

      def use_ssl=(flag)
        flag
      end

      def open_timeout=(seconds)
        seconds
      end

      def read_timeout=(seconds)
        seconds
      end

      def request(_req)
        self.class.responses.shift
      end
    end
    sleeps = []
    described_class.new(
      api_key: api_key,
      http_client: http_class,
      sleep: proc { |s| sleeps << s }
    ).chat(messages: [{ role: "user", content: "hi" }])
    expect(sleeps.first).to eq(3.0)
  end

  it "does not retry on a non-retryable 400" do
    bad = response_double(code: 400, body: "no")
    http_class = Class.new do
      define_singleton_method(:responses) { [bad] }
      def initialize(*)
        nil
      end

      def use_ssl=(flag)
        flag
      end

      def open_timeout=(seconds)
        seconds
      end

      def read_timeout=(seconds)
        seconds
      end

      def request(_req)
        self.class.responses.shift
      end
    end
    expect do
      described_class.new(api_key: api_key, http_client: http_class, max_attempts: 3).chat(
        messages: [{ role: "user", content: "hi" }]
      )
    end.to raise_error(OllamaAgent::AnthropicAPIError, /status=400/)
  end

  # rubocop:disable RSpec/ExampleLength
  it "yields stream deltas from SSE lines" do
    chunks = []
    sse_body = +""
    sse_body << "data: #{JSON.generate(
      "type" => "content_block_delta",
      "delta" => { "type" => "text_delta", "text" => "Hel" }
    )}\n\n"
    sse_body << "data: #{JSON.generate(
      "type" => "message_delta",
      "delta" => { "stop_reason" => "end_turn" }
    )}\n\n"

    stream_response = Object.new
    stream_response.define_singleton_method(:code) { "200" }
    stream_response.define_singleton_method(:read_body) { |&blk| blk.call(sse_body) }

    http_class = Class.new do
      define_method(:request) do |_req, &block|
        block.call(stream_response)
        stream_response
      end

      def initialize(*); end

      def use_ssl=(flag)
        flag
      end

      def open_timeout=(seconds)
        seconds
      end

      def read_timeout=(seconds)
        seconds
      end
    end

    described_class.new(api_key: api_key, http_client: http_class).stream_chat(
      messages: [{ role: "user", content: "hi" }],
      max_tokens: 10
    ) { |c| chunks << c }

    expect(chunks).to eq(
      [
        { delta: "Hel", stop_reason: nil },
        { delta: "", stop_reason: "end_turn" }
      ]
    )
  end
  # rubocop:enable RSpec/ExampleLength
end


require "ollama_client"
require_relative "lib/ollama_agent"

# Mock the client to raise Ollama::HTTPError
class MockClient
  def chat(**args)
    # Simulate HTTP 429 error from ollama-client
    # In ollama-client 1.1.0, handle_http_error raises HTTPError with message
    # status is not a separate attribute in the error itself usually, 
    # but let's see how it looks in the backtrace: 
    # "HTTP 429: you (shubhamtaywade82) have reached your weekly usage limit"
    raise Ollama::HTTPError.new("HTTP 429: you (shubhamtaywade82) have reached your weekly usage limit")
  end
end

# We need to mock Ollama::Config as well because Agent calls it
module Ollama
  class Config
    attr_accessor :model, :timeout
    def initialize
      @model = "llama3"
      @timeout = 30
    end
  end
end

# Initialize agent with mock client wrapped in RetryMiddleware
mock_client = MockClient.new
retry_wrapped = OllamaAgent::Resilience::RetryMiddleware.new(client: mock_client, max_attempts: 2)
agent = OllamaAgent::Agent.new(client: retry_wrapped)

begin
  agent.run("hello")
rescue => e
  puts "Caught error: #{e.class}: #{e.message}"
  puts "Responds to status? #{e.respond_to?(:status)}"
  puts "Status: #{e.status}" if e.respond_to?(:status)
  puts e.backtrace.first(5).join("\n")
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OllamaAgent::OllamaChatThinkingStreamPatch" do
  it "prepends Ollama::Client::Chat so streaming can call hooks[:on_thinking]" do
    unless defined?(Ollama::Client::Chat) &&
           Ollama::Client::Chat.private_method_defined?(:process_chat_stream_chunk, false)
      skip "ollama-client layout changed"
    end

    expect(Ollama::Client.ancestors).to include(OllamaAgent::OllamaChatThinkingStreamPatch)
  end
end

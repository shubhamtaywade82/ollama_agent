# frozen_string_literal: true

# ollama-client streams `message.content` via hooks[:on_token] but only appends `message.thinking`
# to a buffer. Forward thinking deltas so the CLI can render reasoning separately (Cursor-like).
module OllamaAgent
  # Prepends {Ollama::Client::Chat} to invoke optional +hooks[:on_thinking]+ with each thinking chunk.
  module OllamaChatThinkingStreamPatch
    # rubocop:disable Metrics/ParameterLists -- signature must match ollama-client
    def process_chat_stream_chunk(obj, hooks, full_content, full_thinking, full_logprobs, last_data)
      emit_streaming_thinking(hooks, obj)
      super
    end
    # rubocop:enable Metrics/ParameterLists

    private

    def emit_streaming_thinking(hooks, obj)
      return unless obj.is_a?(Hash) && obj["message"].is_a?(Hash)

      th = obj["message"]["thinking"]
      hooks[:on_thinking]&.call(th) if th && !th.to_s.empty?
    end
  end
end

if defined?(Ollama::Client::Chat) &&
   Ollama::Client::Chat.private_method_defined?(:process_chat_stream_chunk, false)
  Ollama::Client::Chat.prepend(OllamaAgent::OllamaChatThinkingStreamPatch)
end

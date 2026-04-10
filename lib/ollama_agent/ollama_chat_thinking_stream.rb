# frozen_string_literal: true

require_relative "chat_stream_thinking_format"
require_relative "chat_stream_carry"

# ollama-client streams `message.content` via hooks[:on_token] but only appends `message.thinking`
# to a buffer. Forward thinking deltas so the CLI can render reasoning separately (Cursor-like).
module OllamaAgent
  # Prepends {Ollama::Client::Chat} to invoke optional +hooks[:on_thinking]+ with each thinking chunk.
  module OllamaChatThinkingStreamPatch
    # rubocop:disable Metrics/ParameterLists -- signature must match ollama-client
    def process_chat_stream_chunk(obj, hooks, full_content, full_thinking, full_logprobs, last_data)
      normalize_stream_thinking_payload!(obj)
      emit_streaming_thinking(hooks, obj)
      ChatStreamCarry.stitch_done_message_tool_calls!(obj, last_data)
      carry = ChatStreamCarry.next_last_data(last_data, obj)
      super(obj, hooks, full_content, full_thinking, full_logprobs, carry)
    end
    # rubocop:enable Metrics/ParameterLists

    private

    def normalize_stream_thinking_payload!(obj)
      return unless obj.is_a?(Hash) && obj["message"].is_a?(Hash)

      ChatStreamThinkingFormat.normalize_message_thinking!(obj["message"])
    end

    def emit_streaming_thinking(hooks, obj)
      return unless obj.is_a?(Hash) && obj["message"].is_a?(Hash)

      th = obj["message"]["thinking"]
      hooks[:on_thinking]&.call(th) if th.is_a?(String) && !th.empty?
    end
  end
end

if defined?(Ollama::Client::Chat) &&
   Ollama::Client::Chat.private_method_defined?(:process_chat_stream_chunk, false)
  Ollama::Client::Chat.prepend(OllamaAgent::OllamaChatThinkingStreamPatch)
end

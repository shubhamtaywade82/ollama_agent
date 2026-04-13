# frozen_string_literal: true

require_relative "chat_stream_thinking_format"
require_relative "chat_stream_carry"
require_relative "gemma_thought_content_parser"

# ollama-client streams `message.content` via hooks[:on_token] but only appends `message.thinking`
# to a buffer. Forward thinking deltas so the CLI can render reasoning separately (Cursor-like).
#
# Gemma 4 (especially cloud) often leaves reasoning inside +message.content+ (channel / redacted tags)
# instead of +message.thinking+; see {GemmaThoughtContentParser}.
module OllamaAgent
  # Prepends {Ollama::Client::Chat} to invoke optional +hooks[:on_thinking]+ with each thinking chunk.
  module OllamaChatThinkingStreamPatch
    # rubocop:disable Metrics/ParameterLists -- signature must match ollama-client
    def process_chat_stream_chunk(obj, hooks, full_content, full_thinking, full_logprobs, last_data)
      normalize_stream_thinking_payload!(obj)
      parse_state = GemmaThoughtContentParser.extract_state(last_data)
      parse_state = extract_gemma_thought_from_stream_content!(obj, hooks, parse_state)
      emit_streaming_thinking(hooks, obj)
      ChatStreamCarry.stitch_done_message_tool_calls!(obj, last_data)
      carry = ChatStreamCarry.next_last_data(last_data, obj)
      GemmaThoughtContentParser.attach_state!(carry, parse_state)
      super(obj, hooks, full_content, full_thinking, full_logprobs, carry)
    end
    # rubocop:enable Metrics/ParameterLists

    private

    def extract_gemma_thought_from_stream_content!(obj, hooks, parse_state)
      msg = obj["message"]
      return parse_state unless obj.is_a?(Hash) && msg.is_a?(Hash)
      return parse_state if msg["thinking"].is_a?(String) && !msg["thinking"].empty?

      content = msg["content"]
      return parse_state if content.nil? || content.empty?

      apply_gemma_content_split!(msg, hooks, parse_state, content)
    end

    def apply_gemma_content_split!(msg, hooks, parse_state, content)
      new_content, new_state, deltas = GemmaThoughtContentParser.process_chunk(parse_state, content)
      msg["content"] = new_content
      deltas.each { |d| hooks[:on_thinking]&.call(d) }
      new_state
    end

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

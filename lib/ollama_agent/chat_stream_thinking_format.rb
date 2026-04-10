# frozen_string_literal: true

module OllamaAgent
  # Coerces streamed +message.thinking+ payloads to a String before ollama-client appends
  # with +full_thinking << thinking+ (which raises TypeError on Hash/Array for some models/APIs).
  module ChatStreamThinkingFormat
    module_function

    def normalize_message_thinking!(message_hash)
      return unless message_hash.is_a?(Hash)

      raw = message_hash["thinking"]
      return if raw.nil? || raw.is_a?(String)

      message_hash["thinking"] = coerce_thinking_to_string(raw)
    end

    def coerce_thinking_to_string(raw)
      case raw
      when String then raw
      when Array then raw.map { |elem| coerce_thinking_to_string(elem) }.join
      else
        JSON.generate(raw)
      end
    rescue JSON::GeneratorError, TypeError
      raw.to_s
    end
  end
end

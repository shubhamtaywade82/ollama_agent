# frozen_string_literal: true

require_relative "chat_stream_thinking_format"

module OllamaAgent
  # Incrementally strips Gemma-style reasoning channels from streamed +message.content+
  # when Ollama does not populate +message.thinking+ (common for Gemma 4 cloud vs Qwen/DeepSeek).
  # +merge_into_message_data!+ also runs {ChatStreamThinkingFormat.normalize_message_thinking!} so Hash/Array
  # +thinking+ payloads from the API are coerced to a String before display (README: Reasoning / thinking output).
  #
  # Supported openings (earliest match wins):
  # - +<|channel>thought+ optionally followed by a single newline before reasoning text
  # - +<redacted_thinking>+
  #
  # Closures pair with the opening:
  # - +<channel|>+ (Gemma / Ollama template style)
  # - +</redacted_thinking>+
  # rubocop:disable Metrics/ModuleLength -- single streaming scanner; splitting would obscure state machine
  module GemmaThoughtContentParser
    module_function

    STATE_KEY = "__ollama_agent_gemma_thought_parse"

    OPEN_SPECS = [
      { key: "channel", open: "<|channel>thought", close: "<channel|>" },
      { key: "redacted", open: "<redacted_thinking>", close: "</redacted_thinking>" }
    ].freeze

    def initial_state
      {
        "phase" => "content",
        "pend" => +"",
        "open_key" => nil
      }
    end

    # @return [Array(String, Hash, Array<String>)] content_for_api, new_state, thinking_deltas
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def process_chunk(state, chunk)
      state = copy_state(state)
      return [nil, state, []] if chunk.nil?

      deltas = []
      content_out = +""
      work = state["pend"] + chunk
      state["pend"] = +""

      until work.empty?
        if state["phase"] == "content"
          earliest = earliest_open(work)
          if earliest.nil?
            hold = longest_open_prefix_suffix(work)
            emit_len = work.length - hold.length
            content_out << work[0, emit_len] if emit_len.positive?
            state["pend"] = hold
            break
          end

          idx, spec = earliest
          olen = spec[:open].length
          content_out << work[0, idx] if idx.positive?
          work = work[(idx + olen)..] || +""
          work = work[1..] if work.start_with?("\n")
          state["phase"] = "thought"
          state["open_key"] = spec[:key]
          next
        end

        spec = OPEN_SPECS.find { |s| s[:key] == state["open_key"] }
        idx = work.index(spec[:close])
        if idx.nil?
          hold = longest_close_prefix_suffix(work, spec[:close])
          emit_len = work.length - hold.length
          part = emit_len.positive? ? work[0, emit_len] : +""
          deltas << part if part != ""
          state["pend"] = hold
          break
        end

        clen = spec[:close].length
        part = work[0, idx]
        deltas << part if part != ""
        work = work[(idx + clen)..] || +""
        work = work[1..] if work.start_with?("\n")
        state["phase"] = "content"
        state["open_key"] = nil
      end

      [content_out, state, deltas]
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    def extract_state(carry)
      return initial_state unless carry.is_a?(Hash)

      raw = carry[STATE_KEY]
      return initial_state if raw.nil? || !raw.is_a?(Hash)

      copy_state(raw)
    end

    def attach_state!(carry, state)
      return unless carry.is_a?(Hash)

      carry[STATE_KEY] = copy_state(state)
    end

    # One-shot parse of a full assistant body (non-streaming chat / TUI).
    # @return [Array(String, String)] [thinking_text, visible_content]; +thinking_text+ is +nil+ when no markers
    def extract_from_complete_content(content)
      c = content.to_s
      return [nil, c] if c.empty?

      new_content, _state, deltas = process_chunk(initial_state, c)
      thinking = deltas.join
      return [nil, c] if thinking.strip.empty?

      [thinking, new_content]
    end

    # Mutates +message+ backing hash when the API omits +thinking+ but embeds Gemma channels in +content+.
    def merge_into_message_data!(message)
      data = message_data_hash(message)
      return unless data

      ChatStreamThinkingFormat.normalize_message_thinking!(data)
      return if native_thinking_present?(data)

      raw_content = (data["content"] || data[:content]).to_s
      return if raw_content.empty?

      thinking_text, visible = extract_from_complete_content(raw_content)
      return if thinking_text.nil? || thinking_text.strip.empty?

      data["thinking"] = thinking_text
      data["content"] = visible
    end

    def copy_state(raw)
      {
        "phase" => raw["phase"].to_s,
        "pend" => +raw["pend"].to_s,
        "open_key" => raw["open_key"]
      }
    end
    private_class_method :copy_state

    def message_data_hash(message)
      return unless message.respond_to?(:to_h)

      h = message.to_h
      h if h.is_a?(Hash)
    end
    private_class_method :message_data_hash

    def native_thinking_present?(data)
      existing = data["thinking"] || data[:thinking]
      existing.is_a?(String) && !existing.strip.empty?
    end
    private_class_method :native_thinking_present?

    def earliest_open(work)
      best = nil
      OPEN_SPECS.each do |spec|
        idx = work.index(spec[:open])
        next if idx.nil?

        best = [idx, spec] if best.nil? || idx < best[0]
      end
      best
    end
    private_class_method :earliest_open

    def max_open_hold_length
      OPEN_SPECS.map { |s| s[:open].length }.max - 1
    end
    private_class_method :max_open_hold_length

    def longest_open_prefix_suffix(work)
      max_hold = max_open_hold_length
      return +"" if max_hold <= 0

      upper = [work.length, max_hold].min
      upper.downto(1) do |len|
        suffix = work[-len, len]
        return suffix if suffix_open_prefix?(suffix)
      end
      +""
    end
    private_class_method :longest_open_prefix_suffix

    def suffix_open_prefix?(suffix)
      suffix && OPEN_SPECS.any? { |sp| sp[:open].start_with?(suffix) }
    end
    private_class_method :suffix_open_prefix?

    def longest_close_prefix_suffix(work, close)
      max_hold = close.length - 1
      return +"" if max_hold <= 0

      upper = [work.length, max_hold].min
      upper.downto(1) do |len|
        suffix = work[-len, len]
        return suffix if suffix && close.start_with?(suffix)
      end
      +""
    end
    private_class_method :longest_close_prefix_suffix
  end
  # rubocop:enable Metrics/ModuleLength
end

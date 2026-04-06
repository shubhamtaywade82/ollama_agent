# frozen_string_literal: true

module OllamaAgent
  # ollama-client 1.1.0 +process_chat_stream_chunk+ returns the *previous* +last_data+ for every
  # non-+done+ line, so +message.tool_calls+ seen on an intermediate NDJSON row are dropped when the
  # final +done+ row omits them. Carry forward merged state and copy +tool_calls+ onto the +done+ row.
  module ChatStreamCarry
    module_function

    def next_last_data(prev, obj)
      return json_dup(obj) if prev.nil? && !truthy_done?(obj)
      return prev if truthy_done?(obj)

      merge_carry(prev, obj)
    end

    def stitch_done_message_tool_calls!(done_obj, prev_carry)
      prev_tc = tool_calls_from_carry(prev_carry)
      return if prev_tc.nil? || !truthy_done?(done_obj)

      apply_tool_calls_to_done!(done_obj, prev_tc)
    end

    def merge_carry(prev, obj)
      merged = json_dup(prev)
      chunk_msg = obj["message"]
      return merged if chunk_msg.nil? || !chunk_msg.is_a?(Hash)

      merge_message_fields!(merged, chunk_msg)
      merged
    end

    def truthy_done?(obj)
      obj.is_a?(Hash) && (obj["done"] == true || obj[:done] == true)
    end

    def json_dup(payload)
      return payload if payload.nil?

      JSON.parse(JSON.generate(payload))
    rescue JSON::GeneratorError, JSON::ParserError, TypeError
      dup_via_marshal(payload)
    end

    def tool_calls_from_carry(prev_carry)
      return unless prev_carry.is_a?(Hash)

      prev_msg = prev_carry["message"]
      return unless prev_msg.is_a?(Hash)

      tc = prev_msg["tool_calls"]
      return tc if tc.is_a?(Array) && !tc.empty?

      nil
    end
    private_class_method :tool_calls_from_carry

    def apply_tool_calls_to_done!(done_obj, prev_tc)
      done_msg = done_obj["message"]
      unless done_msg.is_a?(Hash)
        done_obj["message"] = { "role" => "assistant", "tool_calls" => prev_tc }
        return
      end

      done_tc = done_msg["tool_calls"]
      return if done_tc.is_a?(Array) && !done_tc.empty?

      done_msg["tool_calls"] = prev_tc
    end
    private_class_method :apply_tool_calls_to_done!

    def merge_message_fields!(merged, chunk_msg)
      mm = (merged["message"] ||= {})
      tc = chunk_msg["tool_calls"]
      mm["tool_calls"] = tc if tc.is_a?(Array) && !tc.empty?
      role = chunk_msg["role"]
      mm["role"] = role if role && !role.to_s.strip.empty?
    end
    private_class_method :merge_message_fields!

    def dup_via_marshal(payload)
      Marshal.load(Marshal.dump(payload))
    rescue ArgumentError, TypeError
      payload.dup
    end
    private_class_method :dup_via_marshal
  end
end

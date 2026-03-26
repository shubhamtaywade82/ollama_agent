# frozen_string_literal: true

require "fileutils"
require "json"

module OllamaAgent
  module Resilience
    # Subscribes to Streaming::Hooks and writes structured NDJSON audit logs.
    # Activated by OLLAMA_AGENT_AUDIT=1 or audit: true in Runner.build.
    class AuditLogger
      DEFAULT_MAX_RESULT_BYTES = 4_096

      def initialize(log_dir:, hooks:, max_result_bytes: nil)
        @log_dir          = log_dir
        @hooks            = hooks
        @max_result_bytes = max_result_bytes || env_max_result_bytes
      end

      def attach
        @hooks.on(:on_tool_call)   { |payload| write_entry(tool_call_entry(payload)) }
        @hooks.on(:on_tool_result) { |payload| write_entry(tool_result_entry(payload)) }
        @hooks.on(:on_complete)    { |payload| write_entry(complete_entry(payload)) }
        @hooks.on(:on_error)       { |payload| write_entry(error_entry(payload)) }
        @hooks.on(:on_retry)       { |payload| write_entry(retry_entry(payload)) }
      end

      private

      def write_entry(hash)
        FileUtils.mkdir_p(@log_dir)
        File.open(log_path, "a", encoding: Encoding::UTF_8) { |f| f.puts(JSON.generate(hash)) }
      rescue StandardError
        nil
      end

      def log_path
        File.join(@log_dir, "#{Time.now.strftime("%Y-%m-%d")}.ndjson")
      end

      def ts
        Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      end

      def tool_call_entry(payload)
        { ts: ts, event: "tool_call", name: payload[:name], args: payload[:args], turn: payload[:turn] }
      end

      def tool_result_entry(payload)
        result = payload[:result].to_s
        result = result.byteslice(0, @max_result_bytes) if result.bytesize > @max_result_bytes
        { ts: ts, event: "tool_result", name: payload[:name], bytes: payload[:result].to_s.bytesize,
          result_preview: result, turn: payload[:turn] }
      end

      def complete_entry(payload)
        { ts: ts, event: "agent_complete", turns: payload[:turns] }
      end

      def error_entry(payload)
        { ts: ts, event: "agent_error", error: payload[:error].class.name,
          message: payload[:error].message, turn: payload[:turn] }
      end

      def retry_entry(payload)
        { ts: ts, event: "http_retry", attempt: payload[:attempt],
          delay_ms: payload[:delay_ms], error: payload[:error].class.name }
      end

      def env_max_result_bytes
        v = ENV.fetch("OLLAMA_AGENT_AUDIT_MAX_RESULT_BYTES", nil)
        return DEFAULT_MAX_RESULT_BYTES if v.nil? || v.to_s.strip.empty?

        Integer(v)
      rescue ArgumentError, TypeError
        DEFAULT_MAX_RESULT_BYTES
      end
    end
  end
end

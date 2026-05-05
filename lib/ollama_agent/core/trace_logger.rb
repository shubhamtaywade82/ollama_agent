# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"

module OllamaAgent
  module Core
    # Structured observability logger for agent runs.
    # Tracks: run_id, step_id, tool_call_id, latency, token usage,
    # retry count, fallback usage, schema failures, user approvals.
    #
    # Supports three output modes (set via :format):
    #   :human  — colored, readable (default)
    #   :json   — NDJSON file under log_dir
    #   :debug  — human + full payload dump
    class TraceLogger
      FORMATS = %i[human json debug].freeze

      attr_reader :run_id

      def initialize(log_dir: nil, format: :human, hooks: nil)
        @log_dir = log_dir
        @format  = FORMATS.include?(format.to_sym) ? format.to_sym : :human
        @hooks   = hooks
        @run_id  = "run_#{SecureRandom.hex(8)}"
        @step    = 0

        attach_to_hooks if @hooks
      end

      # Emit a structured trace event.
      # @param event [Symbol] event name
      # @param payload [Hash]
      def trace(event, payload = {})
        entry = build_entry(event, payload)
        write_entry(entry)
        entry
      end

      def start_run(query: nil)
        trace(:run_start, { query: query, run_id: @run_id })
      end

      def end_run(turns:, budget: nil)
        trace(:run_end, { turns: turns, budget: budget&.to_h, run_id: @run_id })
      end

      def tool_call(name:, args:, turn:, call_id: nil)
        @step += 1
        trace(:tool_call, { name: name, args: args, turn: turn,
                            step: @step, call_id: call_id || step_id })
      end

      def tool_result(name:, result:, turn:, latency_ms: nil, call_id: nil)
        trace(:tool_result, { name: name, bytes: result.to_s.bytesize,
                              turn: turn, latency_ms: latency_ms, call_id: call_id })
      end

      def schema_failure(tool:, errors:)
        trace(:schema_failure, { tool: tool, errors: errors })
      end

      def user_approval(tool:, approved:)
        trace(:user_approval, { tool: tool, approved: approved })
      end

      def retry_attempt(attempt:, delay_ms:, error:)
        trace(:http_retry, { attempt: attempt, delay_ms: delay_ms,
                             error: error.class.name, message: error.message })
      end

      def fallback_used(from_provider:, to_provider:, reason:)
        trace(:provider_fallback, { from: from_provider, to: to_provider, reason: reason })
      end

      def loop_detected(summary:)
        trace(:loop_detected, { summary: summary })
      end

      def budget_exceeded(reason:)
        trace(:budget_exceeded, { reason: reason })
      end

      private

      def attach_to_hooks
        @hooks.on(:on_tool_call)   { |p| tool_call(name: p[:name], args: p[:args], turn: p[:turn]) }
        @hooks.on(:on_tool_result) { |p| tool_result(name: p[:name], result: p[:result], turn: p[:turn]) }
        @hooks.on(:on_retry)       { |p| retry_attempt(attempt: p[:attempt], delay_ms: p[:delay_ms], error: p[:error]) }
        @hooks.on(:on_complete)    { |p| end_run(turns: p[:turns]) }
        @hooks.on(:on_error)       do |p|
          trace(:agent_error, { error: p[:error].class.name, message: p[:error].message })
        end
      end

      def build_entry(event, payload)
        { ts: timestamp, run_id: @run_id, event: event }.merge(payload)
      end

      def write_entry(entry)
        case @format
        when :json  then write_json(entry)
        when :debug then write_debug(entry)
        else             write_human(entry)
        end
      rescue StandardError
        nil
      end

      def write_json(entry)
        return unless @log_dir

        FileUtils.mkdir_p(@log_dir)
        path = File.join(@log_dir, "#{Date.today}.trace.ndjson")
        File.open(path, "a", encoding: Encoding::UTF_8) { |f| f.puts(JSON.generate(entry)) }
      end

      def write_human(entry)
        event  = entry[:event].to_s.ljust(20)
        detail = entry.except(:ts, :run_id, :event)
                      .map { |k, v| "#{k}=#{v.inspect}" }.join(" ")
        warn "[#{entry[:ts]}] #{event} #{detail}" if ENV["OLLAMA_AGENT_TRACE"] == "1"
      end

      def write_debug(entry)
        warn "[TRACE] #{JSON.generate(entry)}" if ENV["OLLAMA_AGENT_DEBUG"] == "1"
        write_json(entry) if @log_dir
      end

      def timestamp
        Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
      end

      def step_id
        "step_#{@run_id}_#{@step}"
      end
    end
  end
end

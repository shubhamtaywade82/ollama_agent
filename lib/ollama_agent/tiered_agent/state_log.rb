# frozen_string_literal: true

require "json"

module OllamaAgent
  module TieredAgent
    # Compressed structural state log injected into each planning prompt.
    #
    # Raw console traces and file contents are never fed back into the prompt loop
    # directly; only the summarized state object is. This prevents the KV cache
    # from growing unboundedly across cycles.
    class StateLog
      MAX_FAILURES = 20

      attr_reader :summary, :variables, :failures

      def initialize
        reset!
      end

      # Called after a successful tool invocation.
      def update_success(tool_call)
        @summary = "Successfully executed #{tool_call}."
        @variables["last_executed_tool"] = tool_call
      end

      # Called after a failed verification; caps retained history to MAX_FAILURES.
      def record_failure(tool_call, reason)
        @failures << { "tool" => tool_call, "error" => reason.to_s }
        @failures = @failures.last(MAX_FAILURES)
      end

      # Appends a supervisor recommendation from the large-model escalation pass.
      def append_supervisor_intervention(content)
        @summary = "#{@summary} | Supervisor: #{content.to_s.strip[0, 400]}"
      end

      def set_variable(key, value)
        @variables[key.to_s] = value
      end

      def to_h
        {
          "summary" => @summary,
          "variables" => @variables,
          "failures" => @failures
        }
      end

      def to_json(*)
        JSON.generate(to_h, *)
      end

      def reset!
        @summary   = "Initializing objective status."
        @variables = {}
        @failures  = []
      end
    end
  end
end

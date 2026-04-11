# frozen_string_literal: true

module OllamaAgent
  class Agent
    # HTTP client construction, timeouts, retries, and audit logger attachment.
    module ClientWiring
      private

      def build_default_client
        @http_timeout_seconds = resolved_http_timeout_seconds
        OllamaConnection.retry_wrapped_client(
          timeout: @http_timeout_seconds,
          max_attempts: resolved_max_retries,
          base_url: nil,
          hooks: @hooks,
          base_delay: resolved_retry_base_delay
        )
      end

      def resolved_max_retries
        return @max_retries unless @max_retries.nil?

        EnvConfig.fetch_int(
          "OLLAMA_AGENT_MAX_RETRIES",
          Resilience::RetryMiddleware::DEFAULT_MAX_ATTEMPTS,
          strict: EnvConfig.strict_env?
        )
      end

      def resolved_retry_base_delay
        EnvConfig.fetch_float(
          "OLLAMA_AGENT_RETRY_BASE_DELAY",
          Resilience::RetryMiddleware::DEFAULT_BASE_DELAY,
          strict: EnvConfig.strict_env?
        )
      end

      def resolved_http_timeout_seconds
        parsed = TimeoutParam.parse_positive(@http_timeout_override)
        return parsed if parsed

        raw = ENV.fetch("OLLAMA_AGENT_TIMEOUT", nil)
        parsed = TimeoutParam.parse_positive(raw)
        EnvConfig.warn_invalid("OLLAMA_AGENT_TIMEOUT", raw, DEFAULT_HTTP_TIMEOUT) if malformed_timeout_env?(raw, parsed)

        parsed || DEFAULT_HTTP_TIMEOUT
      end

      def malformed_timeout_env?(raw, parsed)
        raw && !raw.to_s.strip.empty? && parsed.nil?
      end

      def resolved_audit_enabled
        return @audit unless @audit.nil?

        ENV.fetch("OLLAMA_AGENT_AUDIT", "0") == "1"
      end

      def audit_log_dir
        custom = ENV.fetch("OLLAMA_AGENT_AUDIT_LOG_PATH", nil)
        return custom if custom && !custom.to_s.strip.empty?

        File.join(@root, ".ollama_agent", "logs")
      end

      def attach_audit_logger
        Resilience::AuditLogger.new(log_dir: audit_log_dir, hooks: @hooks).attach
      end
    end
  end
end

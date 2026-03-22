# frozen_string_literal: true

module OllamaAgent
  # Parses positive integer seconds for HTTP timeouts (OLLAMA_AGENT_TIMEOUT, CLI --timeout).
  module TimeoutParam
    module_function

    def parse_positive(raw)
      return nil if raw.nil?
      return nil if raw.is_a?(String) && raw.strip.empty?

      t = Integer(raw)
      return nil unless t.positive?

      t
    rescue ArgumentError, TypeError
      nil
    end
  end
end

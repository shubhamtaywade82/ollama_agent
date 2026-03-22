# frozen_string_literal: true

module OllamaAgent
  # Resolves Ollama chat `think:` from CLI override or OLLAMA_AGENT_THINK (ollama-client: true/false/high/medium/low).
  module ThinkParam
    module_function

    def resolve(cli_value)
      raw = cli_value.nil? ? ENV.fetch("OLLAMA_AGENT_THINK", nil) : cli_value
      parse(raw)
    end

    def parse(raw)
      return nil if raw.nil?
      return nil if raw.is_a?(String) && raw.strip.empty?

      s = raw.to_s.strip
      case s.downcase
      when "0", "false", "no", "off" then false
      when "1", "true", "yes", "on" then true
      when "high", "medium", "low" then s.downcase
      else
        s
      end
    end
  end
end

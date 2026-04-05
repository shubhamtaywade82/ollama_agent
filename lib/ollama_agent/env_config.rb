# frozen_string_literal: true

module OllamaAgent
  # Centralized ENV parsing with safe fallbacks; warns on malformed values when OLLAMA_AGENT_DEBUG=1.
  # Set OLLAMA_AGENT_STRICT_ENV=1 to raise {ConfigurationError} on invalid numeric values (CI / operators).
  module EnvConfig
    module_function

    # @return [Boolean] true when +OLLAMA_AGENT_STRICT_ENV=1+ (invalid numeric ENV raises {ConfigurationError}).
    def strict_env?
      ENV["OLLAMA_AGENT_STRICT_ENV"] == "1"
    end

    def warn_invalid(name, raw, fallback)
      return unless ENV["OLLAMA_AGENT_DEBUG"] == "1"

      warn "ollama_agent: #{name}=#{raw.inspect} is invalid; using #{fallback}."
    end

    def fetch_int(name, default, strict: strict_env?)
      v = ENV.fetch(name, nil)
      return default if v.nil? || v.to_s.strip.empty?

      Integer(v)
    rescue ArgumentError, TypeError
      raise ConfigurationError, "ollama_agent: #{name}=#{v.inspect} is not a valid integer" if strict

      warn_invalid(name, v, default)
      default
    end

    def fetch_float(name, default, strict: strict_env?)
      v = ENV.fetch(name, nil)
      return default if v.nil? || v.to_s.strip.empty?

      Float(v)
    rescue ArgumentError, TypeError
      raise ConfigurationError, "ollama_agent: #{name}=#{v.inspect} is not a valid float" if strict

      warn_invalid(name, v, default)
      default
    end
  end
end

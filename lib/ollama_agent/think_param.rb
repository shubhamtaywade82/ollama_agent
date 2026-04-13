# frozen_string_literal: true

module OllamaAgent
  # Resolves Ollama chat `think:` from CLI override or OLLAMA_AGENT_THINK (ollama-client: true/false/high/medium/low).
  module ThinkParam
    module_function

    # GPT-OSS models ignore boolean +think+; Ollama expects +low+, +medium+, or +high+.
    # When the user passes +true+ (CLI/ENV), map to a level so reasoning appears in +message.thinking+.
    #
    # Override default level with +OLLAMA_AGENT_GPT_OSS_THINK+ (+low+, +medium+, or +high+).
    def effective_for_model(parsed, model_name)
      return parsed if parsed.nil?
      return parsed unless parsed == true
      return parsed unless gpt_oss_model_name?(model_name)

      level = ENV.fetch("OLLAMA_AGENT_GPT_OSS_THINK", "medium").to_s.downcase.strip
      return level if %w[low medium high].include?(level)

      "medium"
    end

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

    def gpt_oss_model_name?(model_name)
      model_name.to_s.downcase.include?("gpt-oss")
    end
    private_class_method :gpt_oss_model_name?
  end
end

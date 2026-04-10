# frozen_string_literal: true

module OllamaAgent
  module ExternalAgents
    # Shared ENV parsing for delegate / external agent code paths.
    module EnvHelpers
      class << self
        def env_present?(key)
          v = ENV.fetch(key, nil)
          return false if v.nil?

          !v.to_s.strip.empty?
        end

        def env_bool?(key, default: false)
          ENV.fetch(key, default ? "1" : "0").to_s == "1"
        end

        def env_positive_int(key, default)
          v = ENV.fetch(key, nil)
          return default if v.nil? || v.to_s.strip.empty?

          Integer(v)
        rescue ArgumentError, TypeError
          default
        end

        def integer_or_default(raw, default)
          return default if raw.nil?

          Integer(raw)
        rescue ArgumentError, TypeError
          default
        end
      end
    end
  end
end

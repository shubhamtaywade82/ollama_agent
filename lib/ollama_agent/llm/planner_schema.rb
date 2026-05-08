# frozen_string_literal: true

module OllamaAgent
  module LLM
    # Validates a parsed JSON Hash against a small JSON-schema-shaped allowlist.
    module PlannerSchema
      VALID_JSON_TYPES = %w[string array object number boolean].freeze

      class << self
        def validate(obj, schema)
          err = validate_root_object(obj, schema)
          return [false, err] if err

          props = stringify_keys_shallow(schema["properties"] || schema[:properties] || {})
          err = check_required(obj, schema)
          return [false, err] if err

          err = check_no_extra_keys(obj, props.keys)
          return [false, err] if err

          err = check_property_types(obj, props)
          return [false, err] if err

          [true, nil]
        end

        def validate_root_object(obj, schema)
          return "root must be a JSON object" unless obj.is_a?(Hash)

          root_type = schema["type"] || schema[:type]
          return "schema root type must be 'object'" unless root_type.to_s == "object"

          nil
        end

        def check_required(obj, schema)
          required_keys = Array(schema["required"] || schema[:required]).map(&:to_s)
          required_keys.each do |key|
            return "missing required key #{key}" unless obj.key?(key)
          end
          nil
        end

        def check_no_extra_keys(obj, allowed)
          obj.each_key do |key|
            return "extra key #{key}" unless allowed.include?(key.to_s)
          end
          nil
        end

        def check_property_types(obj, props)
          props.each do |key, spec|
            next unless obj.key?(key)

            ok, err = match_property_type(obj[key], spec)
            return err unless ok
          end
          nil
        end

        def match_property_type(value, spec)
          want = (spec["type"] || spec[:type]).to_s
          return [false, "unknown or missing type for #{want}"] unless VALID_JSON_TYPES.include?(want)

          ok = matches_json_type?(value, want)
          return [true, nil] if ok

          [false, "type mismatch for value #{value.inspect} (expected #{want})"]
        end

        def matches_json_type?(value, want)
          case want
          when "string" then value.is_a?(String)
          when "array" then value.is_a?(Array)
          when "object" then value.is_a?(Hash)
          when "boolean" then [true, false].include?(value)
          when "number" then value.is_a?(Integer) || value.is_a?(Float)
          else false
          end
        end

        def stringify_keys_shallow(hash)
          return {} unless hash.is_a?(Hash)

          hash.transform_keys(&:to_s)
        end
      end
    end
  end
end

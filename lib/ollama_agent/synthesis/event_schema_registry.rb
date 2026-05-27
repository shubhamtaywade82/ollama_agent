# frozen_string_literal: true

module OllamaAgent
  module Synthesis
    # Raised when +validate+ is called for an event that was never +register+ed.
    class UnknownEvent < StandardError; end

    # Minimal JSON-schema-shaped registry (required + property types) for integration payloads.
    class EventSchemaRegistry
      ALLOWED_TYPES = %w[string integer array object boolean].freeze

      def initialize
        @schemas = {}
      end

      def register(event_name:, schema:)
        @schemas[event_name.to_s] = normalize_schema(schema)
      end

      def validate(event_name:, payload:)
        name = event_name.to_s
        raise UnknownEvent, name unless @schemas.key?(name)

        schema = @schemas[name]
        errors = validation_errors(schema, payload)
        { valid: errors.empty?, errors: errors }
      end

      def known_events
        @schemas.keys.sort
      end

      private

      def validation_errors(schema, payload)
        missing_required(schema, payload) + type_mismatches(schema, payload)
      end

      def normalize_schema(schema)
        h = (schema || {}).transform_keys(&:to_s)
        h["properties"] = normalize_properties(h["properties"])
        h["required"] = Array(h["required"]).map(&:to_s)
        h
      end

      def normalize_properties(properties)
        (properties || {}).transform_keys(&:to_s).transform_values { |meta| coerce_meta(meta) }
      end

      def coerce_meta(meta)
        meta.is_a?(Hash) ? meta.transform_keys(&:to_s) : {}
      end

      def missing_required(schema, payload)
        Array(schema["required"]).filter_map do |key|
          "missing required key: #{key}" unless key_present?(payload, key)
        end
      end

      def key_present?(payload, key)
        payload.key?(key) || payload.key?(key.to_sym)
      end

      def type_mismatches(schema, payload)
        props = schema["properties"] || {}
        payload.filter_map { |raw_key, value| property_type_error(raw_key, value, props) }
      end

      def property_type_error(raw_key, value, props)
        key = raw_key.to_s
        meta = props[key]
        return nil unless meta

        type = meta["type"].to_s
        return nil if type.empty?
        return nil if ALLOWED_TYPES.include?(type) && type_matches?(value, type)

        "invalid type for #{key}: expected #{type}, got #{value.class}"
      end

      def type_matches?(value, type)
        case type
        when "string" then value.is_a?(String)
        when "integer" then value.is_a?(Integer)
        when "boolean" then boolean?(value)
        when "array" then value.is_a?(Array)
        when "object" then value.is_a?(Hash)
        else
          false
        end
      end

      def boolean?(value)
        [true, false].include?(value)
      end
    end
  end
end

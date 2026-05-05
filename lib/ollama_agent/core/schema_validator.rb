# frozen_string_literal: true

module OllamaAgent
  module Core
    # Lightweight JSON-schema validator for tool arguments.
    # Supports: type, required, properties, enum, minimum, maximum, minLength, maxLength.
    # Does NOT require the json-schema gem — all validation is hand-rolled for zero dependencies.
    class SchemaValidator
      class ValidationError < StandardError
      end

      # Validate +data+ against +schema+.
      # @param schema [Hash] JSON schema (symbol or string keys)
      # @param data   [Hash] data to validate
      # @return [Array<String>] list of error messages (empty = valid)
      def validate(schema, data)
        @errors = []
        schema  = stringify_keys(schema)
        data    = stringify_keys(data || {})

        check_type(schema, data)
        check_required(schema, data)
        check_properties(schema, data)

        @errors.dup
      end

      # Raises ValidationError if any errors found.
      def validate!(schema, data)
        errors = validate(schema, data)
        raise ValidationError, errors.join("; ") if errors.any?

        true
      end

      private

      def check_type(schema, data)
        expected = schema["type"]
        return if expected.nil?

        actual = ruby_type(data)
        return if type_match?(expected, actual, data)

        @errors << "expected type #{expected}, got #{actual}"
      end

      def check_required(schema, data)
        required = schema["required"]
        return unless required.is_a?(Array)

        required.each do |field|
          @errors << "missing required field: #{field}" unless data.key?(field.to_s)
        end
      end

      def check_properties(schema, data)
        props = schema["properties"]
        return unless props.is_a?(Hash)

        props.each do |prop_name, prop_schema|
          next unless data.key?(prop_name.to_s)

          value = data[prop_name.to_s]
          prop_errors = self.class.new.validate(prop_schema, value)
          prop_errors.each { |e| @errors << "#{prop_name}: #{e}" }
          check_constraints(prop_name, prop_schema, value)
        end
      end

      def check_constraints(name, schema, value)
        check_enum(name, schema, value)
        check_string_length(name, schema, value)
        check_numeric_range(name, schema, value)
      end

      def check_enum(name, schema, value)
        allowed = schema["enum"]
        return unless allowed.is_a?(Array)
        return if allowed.include?(value)

        @errors << "#{name}: must be one of #{allowed.inspect}, got #{value.inspect}"
      end

      def check_string_length(name, schema, value)
        return unless value.is_a?(String)

        min_len = schema["minLength"]
        max_len = schema["maxLength"]

        if min_len && value.length < min_len
          @errors << "#{name}: length #{value.length} is less than minLength #{min_len}"
        end
        return unless max_len && value.length > max_len

        @errors << "#{name}: length #{value.length} exceeds maxLength #{max_len}"
      end

      def check_numeric_range(name, schema, value)
        return unless value.is_a?(Numeric)

        minimum = schema["minimum"]
        maximum = schema["maximum"]

        @errors << "#{name}: #{value} is less than minimum #{minimum}" if minimum && value < minimum
        @errors << "#{name}: #{value} exceeds maximum #{maximum}" if maximum && value > maximum
      end

      def ruby_type(value)
        case value
        when Hash    then "object"
        when Array   then "array"
        when String  then "string"
        when Integer then "integer"
        when Float   then "number"
        when TrueClass, FalseClass then "boolean"
        when NilClass then "null"
        else "unknown"
        end
      end

      def type_match?(expected, actual, data)
        return actual == expected unless expected == "number"

        data.is_a?(Numeric)
      end

      def stringify_keys(obj)
        return obj unless obj.is_a?(Hash)

        obj.transform_keys(&:to_s).transform_values do |v|
          v.is_a?(Hash) ? stringify_keys(v) : v
        end
      end
    end
  end
end

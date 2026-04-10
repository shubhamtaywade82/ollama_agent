# frozen_string_literal: true

module OllamaAgent
  # Normalizes tool call argument hashes (nested "parameters", symbol keys).
  module ToolArguments
    private

    def coerce_tool_arguments(args)
      return {} if args.nil?

      h = args.respond_to?(:to_h) ? args.to_h : {}
      inner = h["parameters"] || h[:parameters]
      return h unless inner.is_a?(Hash)

      # Drop nested parameters in one pass whether the key is String or Symbol.
      outer = h.reject { |k, _| k.to_s == "parameters" }
      merge_parameters_with_outer(inner, outer)
    end

    def merge_parameters_with_outer(inner, outer)
      inner.merge(outer) do |_key, inner_val, outer_val|
        if inner_val.is_a?(Hash) && outer_val.is_a?(Hash)
          merge_parameters_with_outer(inner_val, outer_val)
        else
          inner_val
        end
      end
    end

    def blank_tool_value?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def missing_tool_argument(tool, arg_name)
      "Missing required argument #{arg_name.inspect} for #{tool}."
    end
  end
end

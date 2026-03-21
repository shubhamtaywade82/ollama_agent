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

      inner.merge(h.except("parameters", :parameters))
    end

    def blank_tool_value?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def missing_tool_argument(tool, arg_name)
      "Missing required argument #{arg_name.inspect} for #{tool}."
    end
  end
end

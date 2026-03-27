# frozen_string_literal: true

require "json"

module OllamaAgent
  # Parses JSON tool lines from assistant prose when OLLAMA_AGENT_PARSE_TOOL_JSON=1 (fallback for weak models).
  module ToolContentParser
    KNOWN_TOOLS = %w[list_files read_file search_code edit_file write_file].freeze

    SyntheticToolCall = Struct.new(:id, :name, :arguments)

    def self.enabled?
      ENV["OLLAMA_AGENT_PARSE_TOOL_JSON"] == "1"
    end

    # @return [Array<SyntheticToolCall>] empty if disabled or no parseable lines
    def self.synthetic_calls(content)
      return [] unless enabled?
      return [] if content.nil? || content.to_s.strip.empty?

      content.each_line.with_object([]) do |line, calls|
        parsed = parse_json_tool_line(line, calls.size)
        calls << parsed if parsed
      end
    end

    def self.parse_json_tool_line(line, existing_count)
      stripped = line.strip
      return nil unless stripped.start_with?("{")

      obj = JSON.parse(stripped)
      name = obj["name"]
      return nil unless KNOWN_TOOLS.include?(name)

      args = obj["parameters"] || obj["arguments"] || {}
      args = args.to_h if args.respond_to?(:to_h)

      SyntheticToolCall.new("json-line-#{existing_count + 1}", name, args)
    rescue JSON::ParserError
      nil
    end
    private_class_method :parse_json_tool_line
  end
end

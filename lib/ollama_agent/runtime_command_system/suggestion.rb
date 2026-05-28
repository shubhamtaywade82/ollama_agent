# frozen_string_literal: true

module OllamaAgent
  module RuntimeCommandSystem
    # Immutable completion candidate for the AI Runtime Shell command palette.
    class Suggestion
      attr_reader :text, :type, :description, :metadata, :capabilities, :replacement_start

      def initialize(text:, type:, description: nil, metadata: {}, capabilities: [], replacement_start: 0)
        @text = text.to_s
        @type = type.to_sym
        @description = description
        @metadata = metadata.transform_keys(&:to_sym)
        @capabilities = Array(capabilities).map(&:to_sym)
        @replacement_start = replacement_start.to_i
      end

      def display_text
        name_col = text.ljust(30)
        details = []
        details << description if description && !description.empty?
        badge_str = capabilities.map { |c| "[#{c}]" }.join(" ")
        return text if details.empty? && badge_str.empty?

        suffix = details.empty? ? badge_str : "#{details.join(" ")}  #{badge_str}".rstrip
        "#{name_col}#{suffix}"
      end
    end
  end
end

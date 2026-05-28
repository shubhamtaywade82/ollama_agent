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
        details = []
        details << description if description && !description.empty?
        details.concat(capabilities.map { |capability| "[#{capability}]" })
        details.empty? ? text : "#{text}      #{details.join(" ")}"
      end
    end
  end
end

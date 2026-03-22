# frozen_string_literal: true

module OllamaAgent
  # Modes for search_code that use the Prism Ruby index (single source of truth).
  module RubySearchModes
    ALL = %w[class module constant method].freeze
    CONSTANT_OUTPUT = %w[class module constant].freeze
  end
end

# frozen_string_literal: true

module OllamaAgent
  # Base class for agent failures (use subclasses for rescue specificity).
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class EmptyModelNameError < Error; end

  class EmptyAssistantMessageError < Error; end

  class LocalModelListError < Error; end
end

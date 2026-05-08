# frozen_string_literal: true

module OllamaAgent
  # Base class for agent failures (use subclasses for rescue specificity).
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class EmptyModelNameError < Error; end

  class EmptyAssistantMessageError < Error; end

  class LocalModelListError < Error; end

  # Content-addressed blob store (runtime kernel).
  class BlobNotFound < Error; end

  class BlobIntegrityFault < Error; end

  # Context assembly exceeded a declared section budget (no silent truncation).
  class BudgetExceeded < Error; end

  # Anthropic Messages API returned a non-success HTTP status.
  class AnthropicAPIError < Error; end
end

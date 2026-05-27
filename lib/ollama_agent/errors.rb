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

  # Legacy {Runtime::Permissions}/{Runtime::Policies} disagree with kernel ownership gates.
  class PermissionConflictError < Error
    attr_reader :legacy_allowed, :kernel_allowed

    def initialize(legacy_allowed:, kernel_allowed:, message: nil)
      @legacy_allowed = legacy_allowed
      @kernel_allowed = kernel_allowed
      super(message || "permission conflict: legacy=#{legacy_allowed} kernel=#{kernel_allowed}")
    end
  end

  # Context assembly exceeded a declared section budget (no silent truncation).
  class BudgetExceeded < Error; end

  # Anthropic Messages API returned a non-success HTTP status.
  class AnthropicAPIError < Error; end
end

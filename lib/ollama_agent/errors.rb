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

  # --- Credential Orchestration Runtime ---

  # HTTP 429 where the provider signals a short-window rate limit (RPM/TPM).
  # The credential is placed on a brief cooldown (~60 s); the key remains usable.
  class RateLimitError < Error; end

  # HTTP 429 with quota-exhaustion phrasing, HTTP 402, or daily/monthly limit messages.
  # The credential is placed on a long cooldown (~1 h); the key is deprioritised.
  class QuotaExhaustedError < Error; end

  # HTTP 403 — the model requires an Ollama Pro/Max subscription.
  # This is different from AuthenticationError because the key itself might be valid.
  class SubscriptionRequiredError < Error; end

  # HTTP 401 / 403 — the API key is invalid or revoked.
  # The credential is permanently disabled; never retried.
  class AuthenticationError < Error; end

  # HTTP 5xx or transient network error (timeout, connection refused).
  # The credential is cooled down briefly (~15 s); retried with another key.
  class TemporaryProviderError < Error; end

  # All credentials in the pool are unavailable (disabled, cooling, or exhausted).
  class NoAvailableCredentialError < Error; end
end

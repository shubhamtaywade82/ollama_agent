# frozen_string_literal: true

module TradingAgent
  # Base error for all trading_agent failures.
  class Error < StandardError; end

  # Raised when a trade intent is rejected by the risk layer (caps, kill-switch, whitelist).
  class RiskError < Error; end

  # Raised when an exchange adapter operation fails.
  class ExchangeError < Error; end

  # Raised when the LLM produces output that violates the decision contract.
  class ContractError < Error; end
end

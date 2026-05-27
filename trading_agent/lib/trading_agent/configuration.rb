# frozen_string_literal: true

module TradingAgent
  # Central configuration: credentials, exchange selection, LLM model, and the hard
  # risk caps that live OUTSIDE the LLM's control.
  class Configuration
    # Exchange / connectivity
    attr_accessor :exchange, :testnet, :api_key, :api_secret, :base_url

    # LLM
    attr_accessor :model, :provider, :confidence_threshold

    # Universe
    attr_accessor :symbols

    # Hard risk caps (enforced by Risk::RiskEngine; the LLM can never raise these)
    attr_accessor :max_open_positions, :max_account_risk_percent,
                  :max_leverage, :max_daily_drawdown_percent

    def initialize
      @exchange   = :binance_futures
      @testnet    = true
      @api_key    = ENV.fetch("BINANCE_API_KEY", nil)
      @api_secret = ENV.fetch("BINANCE_API_SECRET", nil)
      @base_url   = nil

      @model                = ENV.fetch("TRADING_AGENT_MODEL", "qwen3.5:14b")
      @provider             = ENV.fetch("TRADING_AGENT_PROVIDER", "ollama")
      @confidence_threshold = 0.6

      @symbols = %w[BTCUSDT ETHUSDT]

      @max_open_positions         = 3
      @max_account_risk_percent   = 5.0
      @max_leverage               = 5
      @max_daily_drawdown_percent = 5.0
    end
  end
end

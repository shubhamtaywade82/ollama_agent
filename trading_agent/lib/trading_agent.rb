# frozen_string_literal: true

require "ollama_agent"

require_relative "trading_agent/version"
require_relative "trading_agent/errors"
require_relative "trading_agent/configuration"
require_relative "trading_agent/event_bus"

# Exchange adapters
require_relative "trading_agent/exchanges/base"
require_relative "trading_agent/exchanges/binance/futures_client"
require_relative "trading_agent/exchanges/binance/websocket_client"
require_relative "trading_agent/exchanges/binance/stream_manager"
require_relative "trading_agent/exchanges/binance/execution_service"

# Market data + deterministic indicators
require_relative "trading_agent/market/candle_store"
require_relative "trading_agent/market/indicator_store"
require_relative "trading_agent/market/market_context"
require_relative "trading_agent/market/symbol_registry"

# Source-of-truth state engine
require_relative "trading_agent/state/state_engine"

# Deterministic strategies
require_relative "trading_agent/strategies/base"
require_relative "trading_agent/strategies/smc_momentum"

# LLM reasoning layer (reuses ollama_agent)
require_relative "trading_agent/llm/decision_schema"
require_relative "trading_agent/llm/trade_evaluator"
require_relative "trading_agent/llm/response_validator"
require_relative "trading_agent/llm/tools"

# Risk + execution
require_relative "trading_agent/risk/guards"
require_relative "trading_agent/risk/position_sizer"
require_relative "trading_agent/risk/risk_engine"
require_relative "trading_agent/execution/order_manager"
require_relative "trading_agent/execution/position_manager"

# Persistence
require_relative "trading_agent/persistence/sqlite_store"

# Orchestration
require_relative "trading_agent/runner"

# Event-driven autonomous trading runtime. The deterministic runtime owns market data,
# state, risk, and execution; the LLM (via ollama_agent) only emits structured trade intents.
module TradingAgent
  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
      configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def logger
      OllamaAgent.logger
    end
  end
end

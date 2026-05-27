# frozen_string_literal: true

module TradingAgent
  module Llm
    class ToolRegistry
      def self.register_all(state, exchange)
        # 1. fetch_market_context
        OllamaAgent::Tools.register(
          :fetch_market_context,
          schema: {
            description: "Retrieve current price, indicators (SMA, EMA, RSI, ATR), account balances, and open positions for a symbol.",
            parameters: {
              type: "object",
              properties: {
                symbol: { type: "string", description: "Symbol to fetch, e.g., BTCUSDT" }
              },
              required: ["symbol"]
            }
          }
        ) do |args, context|
          symbol = (args[:symbol] || args["symbol"] || "BTCUSDT").upcase
          
          # Get price
          price = state.get_price(symbol)
          if price.nil? || price.zero?
            begin
              ticker = exchange.fetch_ticker(symbol)
              price = ticker[:price]
              state.update_price(symbol, price)
            rescue StandardError
              price = 0.0
            end
          end

          # Get candles & calculate indicators
          candles = state.get_candles(symbol, "1h")
          if candles.empty?
            begin
              candles = exchange.fetch_candles(symbol, "1h", limit: 100)
              state.update_candles(symbol, "1h", candles)
            rescue StandardError
              # ignore
            end
          end

          rsi = Market::Indicators.rsi(candles, 14)
          ema = Market::Indicators.ema(candles, 20)
          sma = Market::Indicators.sma(candles, 20)
          atr = Market::Indicators.atr(candles, 14)

          # Get position
          pos = state.get_position(symbol)
          
          # Get balance
          bal = state.get_balances

          {
            symbol: symbol,
            price: price,
            indicators_1h: {
              rsi: rsi,
              ema_20: ema,
              sma_20: sma,
              atr_14: atr
            },
            position: pos,
            balances: bal,
            daily_drawdown_pct: state.current_drawdown_pct
          }.to_json
        end

        # 2. check_indicators
        OllamaAgent::Tools.register(
          :check_indicators,
          schema: {
            description: "Check technical indicators (SMA, EMA, RSI, ATR) for a symbol on a specific timeframe interval.",
            parameters: {
              type: "object",
              properties: {
                symbol: { type: "string", description: "Symbol, e.g., BTCUSDT" },
                interval: { type: "string", description: "Interval, e.g., 15m, 1h, 4h, 1d" }
              },
              required: ["symbol", "interval"]
            }
          }
        ) do |args, context|
          symbol = (args[:symbol] || args["symbol"] || "BTCUSDT").upcase
          interval = args[:interval] || args["interval"] || "1h"

          candles = state.get_candles(symbol, interval)
          if candles.empty?
            begin
              candles = exchange.fetch_candles(symbol, interval, limit: 100)
              state.update_candles(symbol, interval, candles)
            rescue StandardError
              # ignore
            end
          end

          rsi = Market::Indicators.rsi(candles, 14)
          ema = Market::Indicators.ema(candles, 20)
          sma = Market::Indicators.sma(candles, 20)
          atr = Market::Indicators.atr(candles, 14)

          {
            symbol: symbol,
            interval: interval,
            rsi_14: rsi,
            ema_20: ema,
            sma_20: sma,
            atr_14: atr,
            candle_count: candles.size
          }.to_json
        end
      end
    end
  end
end

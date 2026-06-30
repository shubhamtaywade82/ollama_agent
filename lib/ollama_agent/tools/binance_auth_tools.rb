# frozen_string_literal: true

require "cgi"
require "net/http"
require "json"
require "openssl"
require "uri"

require_relative "base"
require_relative "enhanced_registry"

module OllamaAgent
  module Tools
    # ── Binance Futures authenticated request helper ───────────────────────
    module BinanceFuturesAuth
      module_function

      BINANCE_FAPI = "https://fapi.binance.com"

      def api_key
        ENV.fetch("BINANCE_API_KEY", nil)
      end

      def api_secret
        ENV.fetch("BINANCE_API_SECRET", nil)
      end

      def credentials_present?
        !!(api_key && !api_key.empty? && api_secret && !api_secret.empty?)
      end

      def missing_credentials_error
        "Error: BINANCE_API_KEY and BINANCE_API_SECRET must be set"
      end

      def signed_request(method, path, params = {})
        return missing_credentials_error unless credentials_present?

        params = params.merge(timestamp: (Time.now.to_f * 1000).to_i)
        query  = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
        signature = OpenSSL::HMAC.hexdigest("SHA256", api_secret, query)
        uri_str = "#{BINANCE_FAPI}#{path}?#{query}&signature=#{signature}"
        uri = URI(uri_str)

        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 15, open_timeout: 10) do |http|
          case method
          when :get
            req = Net::HTTP::Get.new(uri)
            req["X-MBX-APIKEY"] = api_key
            http.request(req)
          when :post
            req = Net::HTTP::Post.new(uri)
            req["X-MBX-APIKEY"] = api_key
            req["Content-Type"] = "application/json"
            http.request(req)
          when :delete
            req = Net::HTTP::Delete.new(uri)
            req["X-MBX-APIKEY"] = api_key
            http.request(req)
          else
            raise "Unsupported HTTP method: #{method}"
          end
        end

        raise "HTTP #{resp.code}: #{resp.body[0, 200]}" unless resp.is_a?(Net::HTTPSuccess)

        JSON.parse(resp.body)
      rescue JSON::ParserError
        { error: "Invalid JSON: #{resp.body[0, 200]}" }
      rescue StandardError => e
        { error: e.message }
      end
    end

    # ── Account & Position Tools ───────────────────────────────────────────

    class BinanceAccountBalance < Base
      tool_name        "binance_account_balance"
      tool_description "Get Binance Futures wallet balance and available margin per asset. Requires BINANCE_API_KEY and BINANCE_API_SECRET."
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {},
                    required: []
                  })

      def call(_args, _context = {})
        return BinanceFuturesAuth.missing_credentials_error unless BinanceFuturesAuth.credentials_present?

        data = BinanceFuturesAuth.signed_request(:get, "/fapi/v2/account")
        return data if data.is_a?(Hash) && data.key?("error")

        (data["assets"] || []).map do |a|
          { asset: a["asset"], wallet_balance: a["walletBalance"], available_balance: a["availableBalance"], unrealized_pnl: a["unrealizedProfit"] }
        end
      rescue StandardError => e
        "Error fetching account balance: #{e.message}"
      end
    end

    class BinancePositions < Base
      tool_name        "binance_positions"
      tool_description "Get all open futures positions with entry price, liquidation price, unrealized PnL, and leverage."
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Optional contract symbol to filter by, e.g. BTCUSDT" }
                    },
                    required: []
                  })

      def call(args, _context = {})
        return BinanceFuturesAuth.missing_credentials_error unless BinanceFuturesAuth.credentials_present?

        data = BinanceFuturesAuth.signed_request(:get, "/fapi/v2/positionRisk")
        return data if data.is_a?(Hash) && data.key?("error")

        positions = data.select { |p| p["positionAmt"].to_f != 0 }
        if args["symbol"]
          sym = args["symbol"].to_s.strip.upcase
          positions = positions.select { |p| p["symbol"] == sym }
        end
        positions.map do |p|
          {
            symbol: p["symbol"], side: p["positionSide"], size: p["positionAmt"],
            entry_price: p["entryPrice"], mark_price: p["markPrice"],
            liq_price: p["liquidationPrice"], leverage: p["leverage"],
            unrealized_pnl: p["unrealizedProfit"], margin: p["isolatedMargin"]
          }
        end
      rescue StandardError => e
        "Error fetching positions: #{e.message}"
      end
    end

    class BinanceOpenOrders < Base
      tool_name        "binance_open_orders"
      tool_description "List all open futures orders. Optionally filter by symbol."
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Optional contract symbol to filter by, e.g. BTCUSDT" }
                    },
                    required: []
                  })

      def call(args, _context = {})
        return BinanceFuturesAuth.missing_credentials_error unless BinanceFuturesAuth.credentials_present?

        params = {}
        params[:symbol] = args["symbol"].to_s.strip.upcase if args["symbol"]
        data = BinanceFuturesAuth.signed_request(:get, "/fapi/v1/openOrders", params)
        return data if data.is_a?(Hash) && data.key?("error")

        data.map do |o|
          {
            order_id: o["orderId"], symbol: o["symbol"], side: o["side"],
            type: o["type"], price: o["price"], orig_qty: o["origQty"],
            executed_qty: o["executedQty"], status: o["status"],
            stop_price: o["stopPrice"], time: o["time"]
          }
        end
      rescue StandardError => e
        "Error fetching open orders: #{e.message}"
      end
    end

    # ── Leverage & Execution Tools ─────────────────────────────────────────

    class BinanceSetLeverage < Base
      tool_name        "binance_set_leverage"
      tool_description "Set leverage for a futures contract (1-125x). Only affects new positions."
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:   { type: "string", description: "Contract symbol, e.g. BTCUSDT" },
                      leverage: { type: "integer", description: "Leverage value (1-125)", minimum: 1, maximum: 125 }
                    },
                    required: %w[symbol leverage]
                  })

      def call(args, _context = {})
        return BinanceFuturesAuth.missing_credentials_error unless BinanceFuturesAuth.credentials_present?

        symbol   = args["symbol"].to_s.strip.upcase
        leverage = args["leverage"].to_i.clamp(1, 125)
        data = BinanceFuturesAuth.signed_request(:post, "/fapi/v1/leverage", symbol: symbol, leverage: leverage)
        data.is_a?(Hash) && data["leverage"] ? { symbol: data["symbol"], leverage: data["leverage"], max_notional: data["maxNotionalValue"] } : data
      rescue StandardError => e
        "Error setting leverage: #{e.message}"
      end
    end

    class BinancePlaceOrder < Base
      tool_name        "binance_place_order"
      tool_description "Place a futures order on Binance. Supports MARKET, LIMIT, STOP, TAKE_PROFIT. Always present trade details to user for confirmation before calling."
      tool_risk        :critical
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:      { type: "string", description: "Contract symbol, e.g. BTCUSDT" },
                      side:        { type: "string", description: "BUY or SELL", enum: %w[BUY SELL] },
                      type:        { type: "string", description: "Order type: MARKET, LIMIT, STOP, TAKE_PROFIT, STOP_MARKET, TAKE_PROFIT_MARKET" },
                      quantity:    { type: "string", description: "Order quantity (in coin, e.g. 0.01 BTC)" },
                      price:       { type: "string", description: "Limit price (required for LIMIT/STOP/TAKE_PROFIT)" },
                      stop_price:  { type: "string", description: "Stop price (required for STOP/STOP_MARKET)" },
                      reduce_only: { type: "boolean", description: "Whether to reduce position only (default false)", default: false },
                      time_in_force: { type: "string", description: "GTC, IOC, FOK, or POST_ONLY (default GTC for LIMIT)", default: "GTC" }
                    },
                    required: %w[symbol side type quantity]
                  })

      def call(args, _context = {})
        return BinanceFuturesAuth.missing_credentials_error unless BinanceFuturesAuth.credentials_present?

        params = {
          symbol: args["symbol"].to_s.strip.upcase,
          side: args["side"].to_s.strip.upcase,
          type: args["type"].to_s.strip.upcase,
          quantity: args["quantity"].to_s
        }
        params[:price] = args["price"].to_s if args["price"] && !args["price"].to_s.empty?
        params[:stopPrice] = args["stop_price"].to_s if args["stop_price"] && !args["stop_price"].to_s.empty?
        params[:reduceOnly] = true if args["reduce_only"]
        params[:timeInForce] = args["time_in_force"].to_s if args["time_in_force"] && !args["time_in_force"].to_s.empty?

        data = BinanceFuturesAuth.signed_request(:post, "/fapi/v1/order", params)
        return data if data.is_a?(Hash) && data.key?("error")

        {
          order_id: data["orderId"], symbol: data["symbol"], side: data["side"],
          type: data["type"], price: data["price"], orig_qty: data["origQty"],
          executed_qty: data["executedQty"], status: data["status"],
          avg_price: data["avgPrice"]
        }
      rescue StandardError => e
        "Error placing order: #{e.message}"
      end
    end

    class BinanceCancelOrder < Base
      tool_name        "binance_cancel_order"
      tool_description "Cancel an open futures order by symbol and order ID."
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:   { type: "string", description: "Contract symbol, e.g. BTCUSDT" },
                      order_id: { type: "integer", description: "Order ID from open orders list" }
                    },
                    required: %w[symbol order_id]
                  })

      def call(args, _context = {})
        return BinanceFuturesAuth.missing_credentials_error unless BinanceFuturesAuth.credentials_present?

        symbol   = args["symbol"].to_s.strip.upcase
        order_id = args["order_id"].to_i
        data = BinanceFuturesAuth.signed_request(:delete, "/fapi/v1/order", symbol: symbol, orderId: order_id)
        return data if data.is_a?(Hash) && data.key?("error")

        { status: "cancelled", symbol: data["symbol"], order_id: data["orderId"], orig_qty: data["origQty"] }
      rescue StandardError => e
        "Error cancelling order: #{e.message}"
      end
    end

    # ── Risk Management Tools ──────────────────────────────────────────────

    class BinancePositionSizing < Base
      tool_name        "binance_position_sizing"
      tool_description "Calculate optimal position size based on account balance, risk percentage, entry price, and stop loss. Returns quantity in coin and USD."
      tool_risk        :medium
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      account_balance: { type: "number", description: "Available account balance in USD" },
                      risk_percent:    { type: "number", description: "Risk percentage of account (recommended 1-2)", default: 1.0 },
                      entry_price:     { type: "number", description: "Planned entry price" },
                      stop_price:      { type: "number", description: "Stop loss price" },
                      leverage:        { type: "integer", description: "Planned leverage (1-125)", default: 1 }
                    },
                    required: %w[account_balance entry_price stop_price]
                  })

      def call(args, _context = {})
        balance    = args["account_balance"].to_f
        risk_pct   = args.fetch("risk_percent", 1.0).to_f.clamp(0.1, 100)
        entry      = args["entry_price"].to_f
        stop       = args["stop_price"].to_f
        lev        = args.fetch("leverage", 1).to_i.clamp(1, 125)

        return { error: "Entry price must be > 0" } if entry <= 0
        return { error: "Stop price must differ from entry" } if (entry - stop).abs < 0.0001
        return { error: "Account balance must be > 0" } if balance <= 0

        risk_amount  = balance * risk_pct / 100.0
        price_diff   = (entry - stop).abs
        risk_per_unit = price_diff / entry
        raw_position  = risk_amount / price_diff if price_diff > 0
        raw_position  = risk_amount / (entry * 0.01) if price_diff <= 0
        leveraged     = raw_position * lev
        notional      = leveraged * entry
        risk_pct_acct = (risk_amount / balance * 100).round(2)

        {
          position_size_coin: leveraged.round(6),
          position_size_usd: notional.round(2),
          risk_amount_usd: risk_amount.round(2),
          risk_percent_account: risk_pct_acct,
          leverage: lev,
          entry: entry,
          stop_loss: stop,
          account_balance: balance,
          warning: risk_pct_acct > 2 ? "Risk exceeds 2% of account — consider reducing size or using tighter stop." : nil
        }.compact
      end
    end

    class BinanceRiskCheck < Base
      tool_name        "binance_risk_check"
      tool_description "Perform a full risk assessment of a proposed trade before execution. Checks position size, leverage, and account exposure."
      tool_risk        :medium
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:         { type: "string", description: "Contract symbol, e.g. BTCUSDT" },
                      side:           { type: "string", description: "BUY or SELL" },
                      entry_price:    { type: "number", description: "Planned entry price" },
                      stop_price:     { type: "number", description: "Stop loss price" },
                      take_profit:    { type: "number", description: "Optional take profit price" },
                      quantity:       { type: "number", description: "Position size in coin" },
                      leverage:       { type: "integer", description: "Planned leverage (1-125)", default: 1 },
                      account_balance: { type: "number", description: "Available account balance in USD" }
                    },
                    required: %w[symbol side entry_price stop_price quantity account_balance]
                  })

      def call(args, _context = {})
        symbol   = args["symbol"].to_s.strip.upcase
        side     = args["side"].to_s.strip.upcase
        entry    = args["entry_price"].to_f
        stop     = args["stop_price"].to_f
        tp       = args["take_profit"].to_f if args["take_profit"]
        qty      = args["quantity"].to_f
        lev      = args.fetch("leverage", 1).to_i.clamp(1, 125)
        balance  = args["account_balance"].to_f

        return { error: "Entry price must be > 0" } if entry <= 0
        return { error: "Invalid side: use BUY or SELL" } unless %w[BUY SELL].include?(side)
        return { error: "Quantity must be > 0" } if qty <= 0
        return { error: "Account balance must be > 0" } if balance <= 0
        return { error: "Stop price must differ from entry" } if (entry - stop).abs < 0.0001

        notional       = qty * entry
        price_diff_pct = ((entry - stop).abs / entry * 100).round(2)
        risk_amount    = (entry - stop).abs * qty
        risk_pct       = (risk_amount / balance * 100).round(2)
        sl_distance    = price_diff_pct

        checks = []
        checks << "RISK_EXCEEDS_2PCT: #{risk_pct}% of account at risk (max 2%)" if risk_pct > 2
        checks << "HIGH_LEVERAGE: #{lev}x leverage amplifies liquidation risk" if lev > 20
        checks << "STOP_TOO_TIGHT: stop is only #{sl_distance}% from entry (may trigger on noise)" if sl_distance < 0.5 && sl_distance > 0
        checks << "LARGE_POSITION: position notional (#{notional.round(2)} USD) exceeds account balance (#{balance})" if notional > balance

        if tp && tp > 0
          rr = ((tp - entry).abs / (entry - stop).abs).round(2)
          checks << "LOW_RISK_REWARD: risk/reward ratio #{rr} (aim for ≥ 1.5)" if rr < 1.5
        end

        result = {
          symbol: symbol, side: side, leverage: lev,
          entry: entry, stop_loss: stop, sl_distance_pct: sl_distance,
          notional_usd: notional.round(2),
          risk_amount_usd: risk_amount.round(2),
          risk_pct_account: risk_pct,
          passed: checks.empty?,
          warnings: checks
        }
        result[:take_profit] = tp if tp && tp > 0
        result[:risk_reward] = ((tp - entry).abs / (entry - stop).abs).round(2) if tp && tp > 0
        result
      end
    end

    # ── Registrations ───────────────────────────────────────────────────────

    EnhancedRegistry.register(BinanceAccountBalance)
    EnhancedRegistry.register(BinancePositions)
    EnhancedRegistry.register(BinanceOpenOrders)
    EnhancedRegistry.register(BinanceSetLeverage)
    EnhancedRegistry.register(BinancePlaceOrder)
    EnhancedRegistry.register(BinanceCancelOrder)
    EnhancedRegistry.register(BinancePositionSizing)
    EnhancedRegistry.register(BinanceRiskCheck)
  end
end

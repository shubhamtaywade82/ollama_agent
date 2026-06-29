# frozen_string_literal: true

require "cgi"
require "net/http"
require "json"
require "uri"

require_relative "base"
require_relative "enhanced_registry"

module OllamaAgent
  module Tools
    # ── Internal helpers ─────────────────────────────────────────────────────
    module CryptoHttp
      module_function

      def get(uri_str, timeout: 15)
        uri = URI.parse(uri_str)
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: timeout, open_timeout: 10) do |http|
          req = Net::HTTP::Get.new(uri.request_uri)
          req["Accept"] = "application/json"
          resp = http.request(req)
          raise "HTTP #{resp.code}: #{resp.message}" unless resp.is_a?(Net::HTTPSuccess)

          JSON.parse(resp.body)
        end
      rescue JSON::ParserError
        { error: "Invalid JSON response from #{uri.host}" }
      rescue StandardError => e
        { error: e.message }
      end
    end

    # ── Binance Spot Public Tools ───────────────────────────────────────────

    class BinanceTicker < Base
      tool_name        "binance_ticker"
      tool_description "Get the latest price for a Binance spot trading pair (e.g. BTCUSDT, ETHUSDT)"
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Trading pair symbol, e.g. BTCUSDT" }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol = args["symbol"].to_s.strip.upcase
        result = CryptoHttp.get("https://api.binance.com/api/v3/ticker/price?symbol=#{CGI.escape(symbol)}")
        result.is_a?(Hash) && result["symbol"] ? result : { error: "Unknown symbol: #{symbol}", raw: result }
      end
    end

    class BinanceTicker24hr < Base
      tool_name        "binance_ticker_24hr"
      tool_description "Get 24-hour rolling statistics for a Binance spot pair (price change, volume, high, low, etc.)"
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Trading pair symbol, e.g. BTCUSDT" }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol = args["symbol"].to_s.strip.upcase
        result = CryptoHttp.get("https://api.binance.com/api/v3/ticker/24hr?symbol=#{CGI.escape(symbol)}")
        result.is_a?(Hash) && result["symbol"] ? result : { error: "Unknown symbol: #{symbol}", raw: result }
      end
    end

    class BinanceKlines < Base
      tool_name        "binance_klines"
      tool_description "Get historical kline/candlestick data for a Binance spot pair. Use for charting and technical analysis."
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:   { type: "string", description: "Trading pair symbol, e.g. BTCUSDT" },
                      interval: { type: "string", description: "Kline interval: 1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w, 1M", default: "1h" },
                      limit:    { type: "integer", description: "Number of klines to return (max 1000)", default: 100 }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol   = args["symbol"].to_s.strip.upcase
        interval = args.fetch("interval", "1h").to_s.strip
        limit    = args.fetch("limit", 100).to_i.clamp(1, 1000)
        path = "/api/v3/klines?symbol=#{CGI.escape(symbol)}&interval=#{CGI.escape(interval)}&limit=#{limit}"
        result = CryptoHttp.get("https://api.binance.com#{path}")
        return { error: "Could not fetch klines for #{symbol}", raw: result } unless result.is_a?(Array)

        result.map do |k|
          {
            open_time: k[0], open: k[1], high: k[2], low: k[3], close: k[4],
            volume: k[5], close_time: k[6], quote_volume: k[7],
            trades: k[8], taker_buy_base: k[9], taker_buy_quote: k[10]
          }
        end
      end
    end

    class BinanceDepth < Base
      tool_name        "binance_depth"
      tool_description "Get order book depth for a Binance spot pair (bids/asks with quantities)"
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Trading pair symbol, e.g. BTCUSDT" },
                      limit:  { type: "integer", description: "Number of price levels (5, 10, 20, 50, 100, 500, 1000)", default: 100 }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol = args["symbol"].to_s.strip.upcase
        limit  = args.fetch("limit", 100).to_i
        path   = "/api/v3/depth?symbol=#{CGI.escape(symbol)}&limit=#{limit.clamp(1, 1000)}"
        result = CryptoHttp.get("https://api.binance.com#{path}")
        result.is_a?(Hash) && result.key?("bids") ? result : { error: "Could not fetch depth for #{symbol}", raw: result }
      end
    end

    class BinanceExchangeInfo < Base
      tool_name        "binance_exchange_info"
      tool_description "Get Binance spot exchange info: all trading pairs, status, filters, precision. Optionally filter by symbol."
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Optional trading pair to filter by, e.g. BTCUSDT" }
                    },
                    required: []
                  })

      def call(args, _context = {})
        result = CryptoHttp.get("https://api.binance.com/api/v3/exchangeInfo")
        return { error: "Could not fetch exchange info", raw: result } unless result.is_a?(Hash)

        symbols = result["symbols"] || []
        if args["symbol"]
          sym = args["symbol"].to_s.strip.upcase
          symbols = symbols.select { |s| s["symbol"] == sym }
        end
        {
          timezone: result["timezone"],
          server_time: result["serverTime"],
          symbol_count: symbols.size,
          symbols: symbols.map { |s| s.slice("symbol", "status", "baseAsset", "quoteAsset", "isSpotTradingAllowed", "filters") }
        }
      end
    end

    # ── Binance USDⓈ-M Futures Public Tools ─────────────────────────────────

    class BinanceFuturesTicker < Base
      tool_name        "binance_futures_ticker"
      tool_description "Get the latest mark price and index price for a Binance USDⓈ-M futures contract (e.g. BTCUSDT)"
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Futures contract symbol, e.g. BTCUSDT" }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol = args["symbol"].to_s.strip.upcase
        result = CryptoHttp.get("https://fapi.binance.com/fapi/v1/ticker/price?symbol=#{CGI.escape(symbol)}")
        result.is_a?(Hash) && result["symbol"] ? result : { error: "Unknown futures symbol: #{symbol}", raw: result }
      end
    end

    class BinanceFuturesKlines < Base
      tool_name        "binance_futures_klines"
      tool_description "Get historical kline/candlestick data for a Binance USDⓈ-M futures contract"
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:   { type: "string", description: "Futures contract symbol, e.g. BTCUSDT" },
                      interval: { type: "string", description: "Kline interval: 1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w, 1M", default: "1h" },
                      limit:    { type: "integer", description: "Number of klines to return (max 1500)", default: 100 }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol   = args["symbol"].to_s.strip.upcase
        interval = args.fetch("interval", "1h").to_s.strip
        limit    = args.fetch("limit", 100).to_i.clamp(1, 1500)
        path = "/fapi/v1/klines?symbol=#{CGI.escape(symbol)}&interval=#{CGI.escape(interval)}&limit=#{limit}"
        result = CryptoHttp.get("https://fapi.binance.com#{path}")
        return { error: "Could not fetch futures klines for #{symbol}", raw: result } unless result.is_a?(Array)

        result.map do |k|
          {
            open_time: k[0], open: k[1], high: k[2], low: k[3], close: k[4],
            volume: k[5], close_time: k[6], quote_volume: k[7],
            trades: k[8], taker_buy_base: k[9], taker_buy_quote: k[10]
          }
        end
      end
    end

    class BinanceFuturesDepth < Base
      tool_name        "binance_futures_depth"
      tool_description "Get order book depth for a Binance USDⓈ-M futures contract"
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Futures contract symbol, e.g. BTCUSDT" },
                      limit:  { type: "integer", description: "Number of price levels (5, 10, 20, 50, 100, 500, 1000)", default: 100 }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol = args["symbol"].to_s.strip.upcase
        limit  = args.fetch("limit", 100).to_i
        path   = "/fapi/v1/depth?symbol=#{CGI.escape(symbol)}&limit=#{limit.clamp(1, 1000)}"
        result = CryptoHttp.get("https://fapi.binance.com#{path}")
        result.is_a?(Hash) && result.key?("bids") ? result : { error: "Could not fetch futures depth for #{symbol}", raw: result }
      end
    end

    class BinanceFuturesExchangeInfo < Base
      tool_name        "binance_futures_exchange_info"
      tool_description "Get Binance USDⓈ-M futures exchange info: contract specs, trading schedules, filters"
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Optional contract symbol to filter by, e.g. BTCUSDT" }
                    },
                    required: []
                  })

      def call(args, _context = {})
        result = CryptoHttp.get("https://fapi.binance.com/fapi/v1/exchangeInfo")
        return { error: "Could not fetch futures exchange info", raw: result } unless result.is_a?(Hash)

        symbols = result["symbols"] || []
        if args["symbol"]
          sym = args["symbol"].to_s.strip.upcase
          symbols = symbols.select { |s| s["symbol"] == sym }
        end
        {
          timezone: result["timezone"],
          server_time: result["serverTime"],
          contract_count: symbols.size,
          symbols: symbols.map { |s| s.slice("symbol", "pair", "contractType", "status", "baseAsset", "quoteAsset", "marginAsset", "filters") }
        }
      end
    end

    # ── CoinDCX Public Tools ────────────────────────────────────────────────

    class CoinDcxTicker < Base
      tool_name        "coindcx_ticker"
      tool_description "Get current ticker data from CoinDCX for one or all trading pairs"
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Optional trading pair to filter by, e.g. BTCUSDT. Returns all pairs if omitted." }
                    },
                    required: []
                  })

      def call(args, _context = {})
        result = CryptoHttp.get("https://api.coindcx.com/api/v3/ticker", timeout: 10)
        return { error: "Could not fetch CoinDCX ticker", raw: result } unless result.is_a?(Array)

        if args["symbol"]
          sym = args["symbol"].to_s.strip.upcase
          pair = result.find { |t| t["market"].to_s.strip.upcase == sym }
          return { error: "Unknown CoinDCX pair: #{sym}" } unless pair

          pair
        else
          {
            count: result.size,
            pairs: result.first(20).map { |t| { market: t["market"], last_price: t["last_price"], change_24hr: t["change_24_hours"] } },
            note: "Showing first 20 of #{result.size} pairs. Use symbol filter for a specific pair."
          }
        end
      end
    end

    class CoinDcxKlines < Base
      tool_name        "coindcx_klines"
      tool_description "Get historical kline/candlestick data from CoinDCX"
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:   { type: "string", description: "Trading pair, e.g. BTCUSDT" },
                      interval: { type: "string", description: "Interval: 1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w, 1M", default: "1h" },
                      limit:    { type: "integer", description: "Number of klines to return (max 500)", default: 100 }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol   = args["symbol"].to_s.strip.upcase
        interval = args.fetch("interval", "1h").to_s.strip
        limit    = args.fetch("limit", 100).to_i.clamp(1, 500)
        path = "/api/v3/klines?pair=#{CGI.escape(symbol)}&interval=#{CGI.escape(interval)}&limit=#{limit}"
        result = CryptoHttp.get("https://api.coindcx.com#{path}", timeout: 10)
        return { error: "Could not fetch CoinDCX klines for #{symbol}", raw: result } unless result.is_a?(Array)

        result.map do |k|
          {
            time: k["time"], open: k["open"], high: k["high"],
            low: k["low"], close: k["close"], volume: k["volume"]
          }
        end
      end
    end

    class CoinDcxDepth < Base
      tool_name        "coindcx_depth"
      tool_description "Get order book depth from CoinDCX for a trading pair"
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Trading pair, e.g. BTCUSDT" }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol = args["symbol"].to_s.strip.upcase
        result = CryptoHttp.get("https://api.coindcx.com/api/v3/depth?pair=#{CGI.escape(symbol)}", timeout: 10)
        return { error: "Could not fetch CoinDCX depth for #{symbol}", raw: result } unless result.is_a?(Hash)

        { bids: result["bids"]&.first(20), asks: result["asks"]&.first(20) }
      end
    end

    # ── Binance Futures Public Analysis Tools ─────────────────────────────

    class BinanceFundingRate < Base
      tool_name        "binance_funding_rate"
      tool_description "Get current and historical funding rate for a Binance USDⓈ-M futures contract. Positive = longs pay shorts (bullish sentiment)."
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:   { type: "string", description: "Futures contract symbol, e.g. BTCUSDT" },
                      limit:    { type: "integer", description: "Number of records to return (max 1000)", default: 100 }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol = args["symbol"].to_s.strip.upcase
        limit  = args.fetch("limit", 100).to_i.clamp(1, 1000)
        result = CryptoHttp.get("https://fapi.binance.com/fapi/v1/fundingRate?symbol=#{CGI.escape(symbol)}&limit=#{limit}")
        return { error: "Could not fetch funding rate for #{symbol}", raw: result } unless result.is_a?(Array)

        result.map { |r| { symbol: r["symbol"], funding_time: r["fundingTime"], funding_rate: r["fundingRate"], mark_price: r["markPrice"] } }
      end
    end

    class BinanceOpenInterest < Base
      tool_name        "binance_open_interest"
      tool_description "Get current and 24h trending open interest for a Binance USDⓈ-M futures contract. Use to confirm trend strength."
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Futures contract symbol, e.g. BTCUSDT" }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol = args["symbol"].to_s.strip.upcase
        result = CryptoHttp.get("https://fapi.binance.com/fapi/v1/openInterest?symbol=#{CGI.escape(symbol)}")
        result.is_a?(Hash) && result["symbol"] ? result : { error: "Could not fetch open interest for #{symbol}", raw: result }
      end
    end

    class BinanceOpenInterestHist < Base
      tool_name        "binance_open_interest_hist"
      tool_description "Get historical open interest data for a Binance USDⓈ-M futures contract (useful for trend strength analysis)."
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:   { type: "string", description: "Futures contract symbol, e.g. BTCUSDT" },
                      period:   { type: "string", description: "Interval: 5m, 15m, 30m, 1h, 2h, 4h, 6h, 12h, 1d", default: "1h" },
                      limit:    { type: "integer", description: "Number of records (max 500)", default: 100 }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol = args["symbol"].to_s.strip.upcase
        period = args.fetch("period", "1h").to_s.strip
        limit  = args.fetch("limit", 100).to_i.clamp(1, 500)
        path   = "/futures/data/openInterestHist?symbol=#{CGI.escape(symbol)}&period=#{CGI.escape(period)}&limit=#{limit}"
        result = CryptoHttp.get("https://fapi.binance.com#{path}")
        return { error: "Could not fetch OI history for #{symbol}", raw: result } unless result.is_a?(Array)

        result.map { |r| { timestamp: r["timestamp"], sum_open_interest: r["sumOpenInterest"], sum_open_interest_value: r["sumOpenInterestValue"] } }
      end
    end

    # ── General Utility Tools ──────────────────────────────────────────────

    class CurrentTime < Base
      tool_name        "current_time"
      tool_description "Get the current date and time. Use for time, date, day-of-week, and timestamp queries."
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {},
                    required: []
                  })

      def call(_args, _context = {})
        now = Time.now
        { utc: now.utc.strftime("%Y-%m-%d %H:%M:%S UTC"), unix: now.to_i, local: now.to_s }
      end
    end

    # ── Registrations ───────────────────────────────────────────────────────

    EnhancedRegistry.register(BinanceTicker)
    EnhancedRegistry.register(BinanceTicker24hr)
    EnhancedRegistry.register(BinanceKlines)
    EnhancedRegistry.register(BinanceDepth)
    EnhancedRegistry.register(BinanceExchangeInfo)

    EnhancedRegistry.register(BinanceFuturesTicker)
    EnhancedRegistry.register(BinanceFuturesKlines)
    EnhancedRegistry.register(BinanceFuturesDepth)
    EnhancedRegistry.register(BinanceFuturesExchangeInfo)

    EnhancedRegistry.register(BinanceFundingRate)
    EnhancedRegistry.register(BinanceOpenInterest)
    EnhancedRegistry.register(BinanceOpenInterestHist)

    EnhancedRegistry.register(CoinDcxTicker)
    EnhancedRegistry.register(CoinDcxKlines)
    EnhancedRegistry.register(CoinDcxDepth)

    EnhancedRegistry.register(CurrentTime)
  end
end

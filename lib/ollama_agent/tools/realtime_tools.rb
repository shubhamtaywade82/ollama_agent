# frozen_string_literal: true

require_relative "base"
require_relative "enhanced_registry"
require_relative "crypto_tools"

module OllamaAgent
  module Tools
    class SubscribeMarketData < Base
      tool_name        "subscribe_market_data"
      tool_description "Stream live Binance market data via REST polling: recent trades, 1m/5m klines, or top-20 order book depth. Duration: 1-30s (default 5s). Use for entry timing before executing."
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:   { type: "string", description: "Trading pair symbol, e.g. BTCUSDT" },
                      stream:   { type: "string", description: "Data stream type: trade (live trades), kline_1m, kline_5m, depth20 (top 20 bids/asks)", default: "trade" },
                      duration: { type: "integer", description: "Stream duration in seconds (1-30)", default: 5 }
                    },
                    required: ["symbol"]
                  })

      SAMPLE_COUNT = 3

      def call(args, _context = {})
        symbol   = args["symbol"].to_s.strip.upcase
        stream   = args.fetch("stream", "trade").to_s.strip
        duration = args.fetch("duration", 5).to_i.clamp(1, 30)

        case stream
        when "trade"    then stream_trades(symbol, duration)
        when "kline_1m" then stream_klines(symbol, "1m", duration)
        when "kline_5m" then stream_klines(symbol, "5m", duration)
        when "depth20"  then fetch_depth(symbol)
        else { error: "Unknown stream type: #{stream}. Use: trade, kline_1m, kline_5m, depth20" }
        end
      end

      private

      def stream_trades(symbol, duration)
        samples = []
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        while Process.clock_gettime(Process::CLOCK_MONOTONIC) - start < duration
          raw = CryptoHttp.get("https://api.binance.com/api/v3/trades?symbol=#{CGI.escape(symbol)}&limit=#{SAMPLE_COUNT}")
          if raw.is_a?(Array) && raw.any?
            raw.each { |t| samples << { price: t["price"], qty: t["qty"], time: t["time"], is_buyer_maker: t["isBuyerMaker"] } }
          end
          sleep(0.5)
        end

        prices = samples.map { |s| s[:price].to_f }
        {
          symbol: symbol, stream: "trade", duration_sec: duration,
          samples_collected: samples.size,
          last_price: prices.last&.round(2),
          avg_price: (prices.sum / prices.size).round(2),
          high: prices.max&.round(2), low: prices.min&.round(2),
          sample_entries: samples.last(5)
        }
      end

      def stream_klines(symbol, interval, _duration)
        raw = CryptoHttp.get("https://api.binance.com/api/v3/klines?symbol=#{CGI.escape(symbol)}&interval=#{CGI.escape(interval)}&limit=3")
        return { error: "Could not fetch klines for #{symbol}", raw: raw } unless raw.is_a?(Array)

        candles = raw.map do |k|
          { time: k[0], open: k[1].to_f, high: k[2].to_f, low: k[3].to_f, close: k[4].to_f, volume: k[5].to_f }
        end

        last = candles.last
        {
          symbol: symbol, stream: "kline_#{interval}",
          current: { price: last[:close], open: last[:open], high: last[:high], low: last[:low], volume: last[:volume] },
          candles: candles
        }
      end

      def fetch_depth(symbol)
        raw = CryptoHttp.get("https://api.binance.com/api/v3/depth?symbol=#{CGI.escape(symbol)}&limit=20")
        return { error: "Could not fetch depth for #{symbol}", raw: raw } unless raw.is_a?(Hash) && raw.key?("bids")

        bids = (raw["bids"] || []).map { |b| { price: b[0].to_f, qty: b[1].to_f } }
        asks = (raw["asks"] || []).map { |a| { price: a[0].to_f, qty: a[1].to_f } }

        bid_volume = bids.sum { |b| b[:price] * b[:qty] }.round(2)
        ask_volume = asks.sum { |a| a[:price] * a[:qty] }.round(2)
        spread = (asks.first[:price] - bids.first[:price]).round(2)

        {
          symbol: symbol, stream: "depth20",
          bids: bids.first(10), asks: asks.first(10),
          best_bid: bids.first[:price], best_ask: asks.first[:price],
          spread: spread, bid_volume_usd: bid_volume, ask_volume_usd: ask_volume
        }
      end
    end

    EnhancedRegistry.register(SubscribeMarketData)
  end
end

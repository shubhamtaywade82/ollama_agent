# frozen_string_literal: true

require_relative "base"
require_relative "enhanced_registry"
require_relative "crypto_tools"
require_relative "smc_engines"

module OllamaAgent
  module Tools
    # ── SMC Analysis (legacy — kept for backward compat) ──────────────────
    module SmcAnalysis
      module_function

      def klines_to_candles(raw) = SmcEngines.klines_to_candles(raw)
      def find_swing_highs(candles, lookback = 2)
        SmcEngines.detect_pivots(candles, left_bars: lookback, right_bars: lookback)[:highs]
      end
      def find_swing_lows(candles, lookback = 2)
        SmcEngines.detect_pivots(candles, left_bars: lookback, right_bars: lookback)[:lows]
      end
      def avg_body(candles)
        bodies = candles.map { |c| (c[:close] - c[:open]).abs }
        bodies.sum / bodies.size
      end
      def find_order_blocks(candles, lookback = 2)
        atr = SmcEngines.compute_atr(candles)
        pivots = SmcEngines.detect_pivots(candles, left_bars: lookback, right_bars: lookback)
        displace = SmcEngines.detect_displacement(candles, atr)
        SmcEngines.detect_order_blocks(candles, pivots, displace, atr)
      end
      def find_fvgs(candles)
        fvgs = []
        (1...(candles.size - 1)).each do |i|
          prev = candles[i - 1]; nxt = candles[i + 1]
          if nxt[:low] > prev[:high]
            fvgs << { type: "bullish_fvg", price: (prev[:high] + nxt[:low]) / 2.0, gap_high: nxt[:low], gap_low: prev[:high], time: candles[i][:time] }
          elsif nxt[:high] < prev[:low]
            fvgs << { type: "bearish_fvg", price: (prev[:low] + nxt[:high]) / 2.0, gap_low: nxt[:high], gap_high: prev[:low], time: candles[i][:time] }
          end
        end
        fvgs
      end
      def analyze_trend(candles)
        return "insufficient_data" if candles.size < 20
        recent = candles.last(10)
        earlier = candles.first(10)
        hh = recent.map { |c| c[:high] }.max >= earlier.map { |c| c[:high] }.max
        hl = recent.map { |c| c[:low] }.min >= earlier.map { |c| c[:low] }.min
        if hh && hl then "uptrend"
        elsif !hh && !hl then "downtrend"
        elsif hh && !hl then "potential_reversal_up"
        else "potential_reversal_down"
        end
      end
      def compute_sma(candles, period)
        return nil if candles.size < period
        candles.last(period).sum { |c| c[:close] } / period
      end
      def analyze_timeframe(raw, interval_label) = SmcEngines.full_timeframe_analysis(raw, interval_label)
      TRADING_STYLES = SmcEngines.methods.include?(:timeframes_for_style) ? {} : {
        "scalping" => { entry: "1m", trend: "5m", macro: nil },
        "intraday" => { entry: "15m", trend: "1h", macro: nil },
        "swing" => { entry: "1h", trend: "4h", macro: "1d" },
        "positional" => { entry: "4h", trend: "1d", macro: "1w" }
      }.freeze
      TRADING_STYLES_MAP = {
        "scalping" => { entry: "1m", trend: "5m", macro: nil },
        "intraday" => { entry: "15m", trend: "1h", macro: nil },
        "swing" => { entry: "1h", trend: "4h", macro: "1d" },
        "positional" => { entry: "4h", trend: "1d", macro: "1w" }
      }.freeze
      def timeframes_for_style(style) = TRADING_STYLES_MAP[style] || TRADING_STYLES_MAP["swing"]
      def compute_confluence(results)
        return { bias: "neutral", confidence: 0 } if results.empty?
        trends = results.map { |r| r[:trend] }
        entry_trend = trends.first
        agreement = trends.count { |t| t == entry_trend }
        if agreement == trends.size && %w[uptrend downtrend].include?(entry_trend)
          { bias: entry_trend == "uptrend" ? "long" : "short", confidence: "high", agreement: agreement }
        elsif agreement >= trends.size - 1 && %w[uptrend downtrend].include?(entry_trend)
          { bias: entry_trend == "uptrend" ? "long" : "short", confidence: "medium", agreement: agreement }
        else
          { bias: "neutral", confidence: "low", agreement: agreement, note: "Timeframes disagree — consider waiting for alignment" }
        end
      end
    end

    # ── Existing tools (updated to use engines) ──────────────────────────

    class FindSmcLevels < Base
      tool_name        "find_smc_levels"
      tool_description "Run Smart Money Concepts (SMC) analysis on one timeframe. Returns BOS/CHoCH, order blocks, liquidity sweeps, PD Array, and trend."
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:   { type: "string", description: "Trading pair symbol, e.g. BTCUSDT" },
                      interval: { type: "string", description: "Timeframe: 1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w", default: "1h" },
                      limit:    { type: "integer", description: "Number of klines (min 30, max 500)", default: 100 }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol   = args["symbol"].to_s.strip.upcase
        interval = args.fetch("interval", "1h").to_s.strip
        limit    = args.fetch("limit", 100).to_i.clamp(30, 500)

        raw = CryptoHttp.get("https://api.binance.com/api/v3/klines?symbol=#{CGI.escape(symbol)}&interval=#{CGI.escape(interval)}&limit=#{limit}")
        return { error: "Could not fetch klines for #{symbol}", raw: raw } unless raw.is_a?(Array)

        smc = SmcEngines.full_timeframe_analysis(raw, interval)
        smc.is_a?(Hash) ? smc.merge(symbol: symbol) : smc
      end
    end

    class AnalyzeMultiTf < Base
      tool_name        "analyze_multi_tf"
      tool_description "Multi-timeframe SMC analysis with style support. Runs BOS/CHoCH, OBs, liquidity sweeps, and PD Array across entry/trend/macro TFs. PRIMARY analysis tool."
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:        { type: "string", description: "Trading pair symbol, e.g. BTCUSDT" },
                      trading_style: { type: "string", description: "scalping (1m/5m), intraday (15m/1h), swing (1h/4h/1d), positional (4h/1d/1w)", default: "swing" }
                    },
                    required: ["symbol"]
                  })

      MAX_KLINES = 200

      def call(args, _context = {})
        symbol = args["symbol"].to_s.strip.upcase
        style  = args.fetch("trading_style", "swing").to_s.strip.downcase
        tfs    = SmcAnalysis.timeframes_for_style(style)
        return { error: "Unknown trading style: #{style}. Use: scalping, intraday, swing, positional" } unless tfs

        results = []
        errors  = []

        [tfs[:entry], tfs[:trend], tfs[:macro]].compact.each do |tf|
          raw = CryptoHttp.get("https://api.binance.com/api/v3/klines?symbol=#{CGI.escape(symbol)}&interval=#{CGI.escape(tf)}&limit=#{MAX_KLINES}")
          if raw.is_a?(Hash) && raw.key?(:error)
            errors << "#{tf}: #{raw[:error]}"
            next
          end
          next unless raw.is_a?(Array)

          results << SmcEngines.full_timeframe_analysis(raw, tf)
        end

        return { error: "Could not fetch data for any timeframe", details: errors } if results.empty?

        confluence = SmcAnalysis.compute_confluence(results)
        bias_desc = case confluence[:bias]
                    when "long"  then "Bullish bias — favor long entries"
                    when "short" then "Bearish bias — favor short entries"
                    else "No clear directional bias"
                    end

        {
          symbol: symbol,
          trading_style: style,
          timeframes: results,
          confluence: confluence,
          bias: bias_desc,
          recommendation: if confluence[:confidence] == "high"
                            "#{bias_desc}. All timeframes aligned (#{confluence[:agreement]}/#{results.size})."
                          elsif confluence[:confidence] == "medium"
                            "#{bias_desc}. #{confluence[:agreement]}/#{results.size} agree. Use entry-TF confirmation."
                          else
                            "Mixed signals across timeframes. Wait for alignment or tighter stop."
                          end
        }
      end
    end

    # ── New SMC Deep-Dive Tools ──────────────────────────────────────────

    class AnalyzeMarketStructure < Base
      tool_name        "analyze_market_structure"
      tool_description "Deep-dive BOS/CHoCH detection with HH/LH/HL/LL classification and protected levels. For structural context after multi-TF analysis."
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:   { type: "string", description: "Trading pair symbol, e.g. BTCUSDT" },
                      interval: { type: "string", description: "Timeframe to analyze", default: "1h" },
                      limit:    { type: "integer", description: "Number of klines (min 30, max 500)", default: 150 }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol   = args["symbol"].to_s.strip.upcase
        interval = args.fetch("interval", "1h").to_s.strip
        limit    = args.fetch("limit", 150).to_i.clamp(30, 500)

        raw = CryptoHttp.get("https://api.binance.com/api/v3/klines?symbol=#{CGI.escape(symbol)}&interval=#{CGI.escape(interval)}&limit=#{limit}")
        return { error: "Could not fetch klines for #{symbol}", raw: raw } unless raw.is_a?(Array)

        candles = SmcEngines.klines_to_candles(raw)
        pivots  = SmcEngines.detect_pivots(candles)
        structure = SmcEngines.analyze_market_structure(candles, pivots)
        pd = SmcEngines.analyze_pd_array(pivots)

        {
          symbol: symbol, timeframe: interval,
          current_price: candles.last[:close].round(2),
          trend: structure[:trend],
          choch: structure[:choch],
          structure_events: structure[:structure],
          last_swing_high: structure[:last_swing_high]&.round(2),
          last_swing_low: structure[:last_swing_low]&.round(2),
          protected_high: structure[:protected_high]&.round(2),
          protected_low: structure[:protected_low]&.round(2),
          current_price_vs_structure: structure[:current_price_vs_structure],
          pd_array: pd
        }
      end
    end

    class FindLiquiditySweeps < Base
      tool_name        "find_liquidity_sweeps"
      tool_description "Detect equal highs/lows and confirmed liquidity sweeps with reclaim. Use for entry timing and stop-hunt detection."
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:   { type: "string", description: "Trading pair symbol, e.g. BTCUSDT" },
                      interval: { type: "string", description: "Timeframe to analyze", default: "15m" },
                      limit:    { type: "integer", description: "Number of klines (min 30, max 500)", default: 200 }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol   = args["symbol"].to_s.strip.upcase
        interval = args.fetch("interval", "15m").to_s.strip
        limit    = args.fetch("limit", 200).to_i.clamp(30, 500)

        raw = CryptoHttp.get("https://api.binance.com/api/v3/klines?symbol=#{CGI.escape(symbol)}&interval=#{CGI.escape(interval)}&limit=#{limit}")
        return { error: "Could not fetch klines for #{symbol}", raw: raw } unless raw.is_a?(Array)

        candles = SmcEngines.klines_to_candles(raw)
        pivots  = SmcEngines.detect_pivots(candles)
        sweeps  = SmcEngines.detect_liquidity_sweeps(candles, pivots)
        eq_highs = SmcEngines.find_equal_levels(pivots[:highs], 0.001)
        eq_lows  = SmcEngines.find_equal_levels(pivots[:lows], 0.001)

        {
          symbol: symbol, timeframe: interval,
          current_price: candles.last[:close].round(2),
          equal_highs: eq_highs.last(5).map { |e| { price: e[:price].round(2) } },
          equal_lows: eq_lows.last(5).map { |e| { price: e[:price].round(2) } },
          confirmed_sweeps: sweeps,
          has_active_sweep: sweeps.any? { |s| s[:status] == "confirmed" }
        }
      end
    end

    class FindOrderBlocks < Base
      tool_name        "find_order_blocks"
      tool_description "Detect displacement-confirmed order blocks with mitigation state and BOS context. Use for entry level precision."
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:   { type: "string", description: "Trading pair symbol, e.g. BTCUSDT" },
                      interval: { type: "string", description: "Timeframe to analyze", default: "1h" },
                      limit:    { type: "integer", description: "Number of klines (min 30, max 500)", default: 200 }
                    },
                    required: ["symbol"]
                  })

      def call(args, _context = {})
        symbol   = args["symbol"].to_s.strip.upcase
        interval = args.fetch("interval", "1h").to_s.strip
        limit    = args.fetch("limit", 200).to_i.clamp(30, 500)

        raw = CryptoHttp.get("https://api.binance.com/api/v3/klines?symbol=#{CGI.escape(symbol)}&interval=#{CGI.escape(interval)}&limit=#{limit}")
        return { error: "Could not fetch klines for #{symbol}", raw: raw } unless raw.is_a?(Array)

        candles  = SmcEngines.klines_to_candles(raw)
        pivots   = SmcEngines.detect_pivots(candles)
        atr_vals = SmcEngines.compute_atr(candles)
        displace = SmcEngines.detect_displacement(candles, atr_vals)
        obs      = SmcEngines.detect_order_blocks(candles, pivots, displace, atr_vals)

        {
          symbol: symbol, timeframe: interval,
          current_price: candles.last[:close].round(2),
          order_blocks: obs.map do |ob|
            {
              type: ob[:type], price: ob[:price].round(2),
              zone: "#{ob[:zone_low].round(2)}–#{ob[:zone_high].round(2)}",
              mitigation: ob[:mitigation],
              created_at_bos: ob[:created_at_bos],
              strength: ob[:strength]
            }
          end,
          untouchted_obs: obs.select { |ob| ob[:mitigation] == "untouched" }.map { |ob| ob[:price].round(2) },
          partially_mitigated: obs.select { |ob| ob[:mitigation] == "partially_mitigated" }.map { |ob| ob[:price].round(2) }
        }
      end
    end

    class IdentifyTradeSetup < Base
      tool_name        "identify_trade_setup"
      tool_description "FLAGSHIP tool: full SMC pipeline across multi-TF. Calls all engines and returns concrete entry/SL/TP1-3 with R:R. Use for trade decisions."
      tool_risk        :low
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:        { type: "string", description: "Trading pair symbol, e.g. BTCUSDT" },
                      trading_style: { type: "string", description: "scalping, intraday, swing, positional", default: "swing" }
                    },
                    required: ["symbol"]
                  })

      MAX_KLINES = 200

      def call(args, _context = {})
        symbol = args["symbol"].to_s.strip.upcase
        style  = args.fetch("trading_style", "swing").to_s.strip.downcase
        tfs    = SmcAnalysis.timeframes_for_style(style)
        return { error: "Unknown trading style: #{style}. Use: scalping, intraday, swing, positional" } unless tfs

        entry_tf = tfs[:entry]
        trend_tf = tfs[:trend]

        raw_entry = CryptoHttp.get("https://api.binance.com/api/v3/klines?symbol=#{CGI.escape(symbol)}&interval=#{CGI.escape(entry_tf)}&limit=#{MAX_KLINES}")
        raw_trend = CryptoHttp.get("https://api.binance.com/api/v3/klines?symbol=#{CGI.escape(symbol)}&interval=#{CGI.escape(trend_tf)}&limit=#{MAX_KLINES}")
        raw_macro = tfs[:macro] ? CryptoHttp.get("https://api.binance.com/api/v3/klines?symbol=#{CGI.escape(symbol)}&interval=#{CGI.escape(tfs[:macro])}&limit=#{MAX_KLINES}") : nil

        return { error: "Could not fetch entry TF klines" } unless raw_entry.is_a?(Array)
        return { error: "Could not fetch trend TF klines" } unless raw_trend.is_a?(Array)

        entry_candles = SmcEngines.klines_to_candles(raw_entry)
        trend_candles = SmcEngines.klines_to_candles(raw_trend)
        macro_candles = raw_macro.is_a?(Array) ? SmcEngines.klines_to_candles(raw_macro) : nil

        trend_atr   = SmcEngines.compute_atr(trend_candles)
        trend_pivots = SmcEngines.detect_pivots(trend_candles)
        trend_struct = SmcEngines.analyze_market_structure(trend_candles, trend_pivots)
        trend_displace = SmcEngines.detect_displacement(trend_candles, trend_atr)
        trend_obs    = SmcEngines.detect_order_blocks(trend_candles, trend_pivots, trend_displace, trend_atr)
        trend_sweeps = SmcEngines.detect_liquidity_sweeps(trend_candles, trend_pivots)

        entry_atr   = SmcEngines.compute_atr(entry_candles)
        entry_pivots = SmcEngines.detect_pivots(entry_candles)
        entry_struct = SmcEngines.analyze_market_structure(entry_candles, entry_pivots)
        entry_displace = SmcEngines.detect_displacement(entry_candles, entry_atr)
        entry_obs    = SmcEngines.detect_order_blocks(entry_candles, entry_pivots, entry_displace, entry_atr)
        entry_sweeps = SmcEngines.detect_liquidity_sweeps(entry_candles, entry_pivots)
        entry_pd     = SmcEngines.analyze_pd_array(entry_pivots)
        entry_confirm = SmcEngines.check_entry_confirmation(entry_candles)

        pb7 = SmcEngines.detect_pb7_sweep_ob(entry_candles, entry_pivots, entry_obs, entry_sweeps, entry_atr)
        pb3 = SmcEngines.detect_pb3_bos_pullback(entry_candles, entry_pivots, entry_obs, entry_struct, entry_atr)

        setups = []
        setups << pb7 if pb7
        setups << pb3 if pb3

        direction = nil
        if trend_struct[:trend] == "uptrend"
          direction = "long"
        elsif trend_struct[:trend] == "downtrend"
          direction = "short"
        end

        has_entry_confirmation = entry_confirm.is_a?(Hash) && entry_confirm[:signal] != "none"

        {
          symbol: symbol, trading_style: style,
          trend_tf: trend_struct,
          entry_tf_analysis: {
            price: entry_candles.last[:close].round(2),
            trend: entry_struct[:trend],
            order_blocks: entry_obs.last(5).map { |ob|
              { type: ob[:type], price: ob[:price].round(2), mitigation: ob[:mitigation] }
            },
            sweeps: entry_sweeps.last(3),
            pd_array: entry_pd,
            entry_confirmation: entry_confirm
          },
          setups_found: setups,
          has_setup: !setups.empty?,
          has_entry_confirmation: has_entry_confirmation,
          recommended_direction: direction,
          summary: if setups.any?
                     s = setups.first
                     "#{s[:setup]} — #{s[:direction]} #{symbol}. Entry #{s[:entry]}, SL #{s[:stop_loss]}, TP1 #{s[:take_profit_1]} (1R), TP2 #{s[:take_profit_2]} (2R), TP3 #{s[:take_profit_3]} (3R)."
                   elsif direction
                     "#{direction.upcase} bias on trend TF. No active entry setup — use analyze_market_structure, find_liquidity_sweeps, find_order_blocks for precision levels."
                   else
                     "No clear directional bias. Mixed structure across timeframes."
                   end
        }
      end
    end

    # ── Registrations ───────────────────────────────────────────────────────

    EnhancedRegistry.register(FindSmcLevels)
    EnhancedRegistry.register(AnalyzeMultiTf)
    EnhancedRegistry.register(AnalyzeMarketStructure)
    EnhancedRegistry.register(FindLiquiditySweeps)
    EnhancedRegistry.register(FindOrderBlocks)
    EnhancedRegistry.register(IdentifyTradeSetup)
  end
end

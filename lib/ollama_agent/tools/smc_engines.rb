# frozen_string_literal: true

module OllamaAgent
  module Tools
    # ── SMC Engines — pure computation, ported from smc-backtester ─────────
    module SmcEngines
      module_function

      # ── Candle conversion ──────────────────────────────────────────────

      def klines_to_candles(raw_klines)
        raw_klines.map do |k|
          { time: k[0], open: k[1].to_f, high: k[2].to_f, low: k[3].to_f,
            close: k[4].to_f, volume: k[5].to_f }
        end
      end

      # ── ATR (Wilder smoothing, period 14) ──────────────────────────────

      def compute_atr(candles, period = 14)
        return [] if candles.size < period + 1
        trs = (1...candles.size).map do |i|
          prev = candles[i - 1]
          c = candles[i]
          [c[:high] - c[:low], (c[:high] - prev[:close]).abs, (c[:low] - prev[:close]).abs].max
        end
        atr = [trs.first(period).sum / period]
        trs[period..].each { |tr| atr << (atr.last * (period - 1) + tr) / period }
        atr
      end

      # ── PivotDetector (swing highs/lows with left/right bars) ──────────

      def detect_pivots(candles, left_bars: 2, right_bars: 2)
        highs = []
        lows = []
        ((left_bars)...(candles.size - right_bars)).each do |i|
          left_vals_h = (1..left_bars).map { |o| candles[i][:high] - candles[i - o][:high] }
          right_vals_h = (1..right_bars).map { |o| candles[i][:high] - candles[i + o][:high] }
          if left_vals_h.all?(&:positive?) && right_vals_h.all?(&:positive?)
            highs << { index: i, price: candles[i][:high], time: candles[i][:time] }
          end
          left_vals_l = (1..left_bars).map { |o| candles[i - o][:low] - candles[i][:low] }
          right_vals_l = (1..right_bars).map { |o| candles[i + o][:low] - candles[i][:low] }
          if left_vals_l.all?(&:positive?) && right_vals_l.all?(&:positive?)
            lows << { index: i, price: candles[i][:low], time: candles[i][:time] }
          end
        end
        { highs: highs, lows: lows }
      end

      # ── MarketStructure (BOS/CHoCH, HH/LH/HL/LL, protected levels) ─────

      def analyze_market_structure(candles, pivots)
        highs = pivots[:highs].map { |h| h[:price] }
        lows  = pivots[:lows].map { |l| l[:price] }
        return { structure: "insufficient_pivots" } if highs.size < 3 || lows.size < 3

        last_price = candles.last[:close]
        structure = []

        highs.each_cons(3).each_with_index do |(a, b, c), i|
          if c > a && b <= a && c > b
            structure << { type: "bullish_bos", index: i + 2, price: c, label: "BOS (break above #{a.round(2)})" }
          elsif c < a && b >= a && c < b
            structure << { type: "bearish_bos", index: i + 2, price: c, label: "BOS (break below #{a.round(2)})" }
          end
        end

        sequential = []
        highs.each_with_index { |h, i| sequential << { type: "high", price: h } }
        lows.each_with_index  { |l, i| sequential << { type: "low", price: l } }
        sequential.sort_by! { |s| s[:price] }

        hh = highs.last(2).size == 2 ? highs[-1] > highs[-2] : nil
        hl = lows.last(2).size == 2 ? lows[-1] < lows[-2] : nil
        if highs.size >= 2 && lows.size >= 2
          last_high = highs[-1]; prev_high = highs[-2]
          last_low  = lows[-1];  prev_low  = lows[-2]
          higher_h = last_high > prev_high
          higher_l = last_low  > prev_low
          if higher_h && higher_l
            trend = "uptrend"
            choch = "none"
          elsif !higher_h && !higher_l
            trend = "downtrend"
            choch = "none"
          elsif !higher_h && higher_l
            trend = "potential_reversal_down"
            choch = "bearish_choch" unless structure.empty?
          else
            trend = "potential_reversal_up"
            choch = "bullish_choch" unless structure.empty?
          end
        else
          trend = "insufficient_data"
          choch = "none"
        end

        protected_high = structure.reverse.find { |s| s[:type] == "bullish_bos" }
        protected_low  = structure.reverse.find { |s| s[:type] == "bearish_bos" }

        {
          structure: structure.last(5),
          trend: trend,
          choch: choch || "none",
          last_swing_high: highs.last,
          last_swing_low: lows.last,
          protected_high: protected_high ? protected_high[:price] : nil,
          protected_low: protected_low ? protected_low[:price] : nil,
          current_price_vs_structure: if last_price > (highs.last || Float::INFINITY)
                                         "above_last_swing_high"
                                       elsif last_price < (lows.last || 0)
                                         "below_last_swing_low"
                                       else
                                         "within_range"
                                       end
        }
      end

      # ── Displacement (body 1.5x ATR, range 2x ATR, min body 60%) ──────

      def detect_displacement(candles, atr_values, atr_period = 14)
        return [] if atr_values.empty?
        displacement = []
        atr_offset = atr_period
        (atr_offset...candles.size).each do |i|
          atr = atr_values[i - atr_offset]
          next if atr.nil? || atr == 0
          c = candles[i]
          body = (c[:close] - c[:open]).abs
          range = c[:high] - c[:low]
          body_is_strong = body >= atr * 1.5 || range >= atr * 2.0
          body_pct = range > 0 ? body / range : 0
          next unless body_is_strong && body_pct >= 0.6

          displacement << {
            index: i, time: c[:time],
            body: body.round(2), range: range.round(2),
            atr: atr.round(2), body_pct: body_pct.round(2),
            direction: c[:close] > c[:open] ? "bullish" : "bearish"
          }
        end
        displacement
      end

      # ── OrderBlock (creation at BOS, mitigation, invalidation) ─────────

      def detect_order_blocks(candles, pivots, displacement, atr_values, atr_period = 14)
        ob_map = []
        atr_offset = atr_period
        pivot_indices = (pivots[:highs] + pivots[:lows]).map { |p| p[:index] }.to_set
        displacement_indices = displacement.map { |d| d[:index] }.to_set

        (2...candles.size).each do |i|
          prev = candles[i - 1]
          curr = candles[i]
          nxt  = i + 1 < candles.size ? candles[i + 1] : nil
          next unless nxt

          curr_dir = curr[:close] > curr[:open] ? "bullish" : "bearish"
          nxt_dir  = nxt[:close] > nxt[:open] ? "bullish" : "bearish"
          next unless curr_dir != nxt_dir

          atr = atr_offset <= i && i - atr_offset < atr_values.size ? atr_values[i - atr_offset] : nil
          next unless atr && atr > 0

          body_curr = (curr[:close] - curr[:open]).abs
          body_next = (nxt[:close] - nxt[:open]).abs
          next unless body_next > atr * 0.8

          is_at_bos = pivot_indices.include?(i) || displacement_indices.include?(i)

          if curr_dir == "bearish" && nxt_dir == "bullish"
            ob_map << { type: "bullish_ob", price: [curr[:open], curr[:close]].max,
                        low: curr[:low], high: curr[:high], time: curr[:time],
                        created_at_bos: is_at_bos, strength: (body_next / atr).round(1),
                        zone_low: curr[:low], zone_high: curr[:high] }
          elsif curr_dir == "bullish" && nxt_dir == "bearish"
            ob_map << { type: "bearish_ob", price: [curr[:open], curr[:close]].min,
                        low: curr[:low], high: curr[:high], time: curr[:time],
                        created_at_bos: is_at_bos, strength: (body_next / atr).round(1),
                        zone_low: curr[:low], zone_high: curr[:high] }
          end
        end

        ob_map.each do |ob|
          latest_price = candles.last[:close]
          if ob[:type] == "bullish_ob"
            if latest_price < ob[:zone_low]
              ob[:mitigation] = "invalidated"
            elsif latest_price <= ob[:zone_high]
              ob[:mitigation] = "partially_mitigated"
            else
              ob[:mitigation] = "untouched"
            end
          else
            if latest_price > ob[:zone_high]
              ob[:mitigation] = "invalidated"
            elsif latest_price >= ob[:zone_low]
              ob[:mitigation] = "partially_mitigated"
            else
              ob[:mitigation] = "untouched"
            end
          end
        end
        ob_map
      end

      # ── LiquiditySweep (equal highs/lows tolerance, sweep+reclaim) ─────

      def detect_liquidity_sweeps(candles, pivots, tolerance: 0.001)
        sweeps = []
        eq_highs = find_equal_levels(pivots[:highs], tolerance)
        eq_lows   = find_equal_levels(pivots[:lows], tolerance)

        eq_highs.each do |eq|
          target_price = eq[:price]
          sweep_idx = candles.index { |c| c[:high] > target_price * (1 + tolerance) && c[:high] > target_price }
          next unless sweep_idx
          reclaim = candles[(sweep_idx + 1)...].find { |c| c[:close] < target_price }
          next unless reclaim

          sweeps << {
            type: "liquidity_sweep_high", level: target_price.round(2),
            sweep_time: candles[sweep_idx][:time],
            reclaim_time: reclaim[:time],
            status: "confirmed"
          }
        end

        eq_lows.each do |eq|
          target_price = eq[:price]
          sweep_idx = candles.index { |c| c[:low] < target_price * (1 - tolerance) && c[:low] < target_price }
          next unless sweep_idx
          reclaim = candles[(sweep_idx + 1)...].find { |c| c[:close] > target_price }
          next unless reclaim

          sweeps << {
            type: "liquidity_sweep_low", level: target_price.round(2),
            sweep_time: candles[sweep_idx][:time],
            reclaim_time: reclaim[:time],
            status: "confirmed"
          }
        end
        sweeps
      end

      def find_equal_levels(pivot_list, tolerance)
        levels = []
        pivot_list.each_cons(2) do |a, b|
          diff = (a[:price] - b[:price]).abs / [a[:price], b[:price]].max
          if diff <= tolerance
            levels << { price: a[:price], index_a: a[:index], index_b: b[:index] }
          end
        end
        levels
      end

      # ── EntryConfirmation (engulfing, rejection wicks) ─────────────────

      def check_entry_confirmation(candles, lookback: 1)
        return "insufficient_data" if candles.size < lookback + 2
        curr = candles[-1]
        prev = candles[-2]
        body_c = (curr[:close] - curr[:open]).abs
        body_p = (prev[:close] - prev[:open]).abs
        range_c = curr[:high] - curr[:low]
        upper_w = curr[:high] - [curr[:open], curr[:close]].max
        lower_w = [curr[:open], curr[:close]].min - curr[:low]

        if curr[:close] > curr[:open] && prev[:close] < prev[:open] && body_c > body_p && curr[:open] < prev[:close] && curr[:close] > prev[:open]
          { signal: "bullish_engulfing", price: curr[:close], strength: (body_c / body_p).round(1) }
        elsif curr[:close] < curr[:open] && prev[:close] > prev[:open] && body_c > body_p && curr[:open] > prev[:close] && curr[:close] < prev[:open]
          { signal: "bearish_engulfing", price: curr[:close], strength: (body_c / body_p).round(1) }
        elsif curr[:close] > curr[:open] && lower_w >= body_c * 2 && range_c > 0 && (curr[:close] - curr[:low]) / range_c > 0.6
          { signal: "bullish_rejection", price: curr[:close], wick_ratio: (lower_w / body_c).round(1) }
        elsif curr[:close] < curr[:open] && upper_w >= body_c * 2 && range_c > 0 && (curr[:high] - curr[:close]) / range_c > 0.6
          { signal: "bearish_rejection", price: curr[:close], wick_ratio: (upper_w / body_c).round(1) }
        else
          { signal: "none" }
        end
      end

      # ── PDArray (equilibrium, discount/premium zones) ──────────────────

      def analyze_pd_array(pivots)
        highs = pivots[:highs].map { |h| h[:price] }
        lows  = pivots[:lows].map { |l| l[:price] }
        return { error: "insufficient_pivots" } if highs.empty? || lows.empty?

        range_high = highs.max
        range_low  = lows.min
        equilibrium = (range_high + range_low) / 2.0
        discount_mid = (range_low + equilibrium) / 2.0
        premium_mid  = (range_high + equilibrium) / 2.0

        {
          range_high: range_high.round(2), range_low: range_low.round(2),
          equilibrium: equilibrium.round(2),
          discount_zone: { low: range_low.round(2), high: equilibrium.round(2), mid: discount_mid.round(2) },
          premium_zone: { low: equilibrium.round(2), high: range_high.round(2), mid: premium_mid.round(2) },
          current_location: "unknown"
        }
      end

      # ── TradeSetups (PB-7 Sweep+OB, PB-3 BOS Pullback) ─────────────────

      def detect_pb7_sweep_ob(candles, pivots, order_blocks, sweeps, atr_values, atr_period = 14)
        return nil if sweeps.empty? || order_blocks.empty? || atr_values.empty?

        sweep = sweeps.last
        matching_obs = order_blocks.select do |ob|
          if sweep[:type] == "liquidity_sweep_high"
            ob[:type] == "bearish_ob" && ob[:zone_high] < sweep[:level] * 0.995
          else
            ob[:type] == "bullish_ob" && ob[:zone_low] > sweep[:level] * 1.005
          end
        end
        return nil if matching_obs.empty?

        ob = matching_obs.last
        atr = atr_values.last || atr_values[-2] || 0
        entry = ob[:type] == "bullish_ob" ? ob[:zone_high] : ob[:zone_low]
        sl = ob[:type] == "bullish_ob" ? ob[:zone_low] - atr * 0.5 : ob[:zone_high] + atr * 0.5
        risk = (entry - sl).abs
        return nil if risk <= 0

        {
          setup: "PB-7 Sweep+OB",
          direction: ob[:type] == "bullish_ob" ? "long" : "short",
          entry: entry.round(2),
          stop_loss: sl.round(2),
          take_profit_1: (entry + risk).round(2),
          take_profit_2: (entry + risk * 2).round(2),
          take_profit_3: (entry + risk * 3).round(2),
          risk_reward_1: 1.0, risk_reward_2: 2.0, risk_reward_3: 3.0,
          order_block_price: ob[:price].round(2),
          sweep_level: sweep[:level]
        }
      end

      def detect_pb3_bos_pullback(candles, pivots, order_blocks, structure, atr_values, atr_period = 14)
        struct_events = structure[:structure]
        struct_events = [] unless struct_events.is_a?(Array)
        bos_events = struct_events.select { |s| s.is_a?(Hash) && s[:type].to_s.include?("bos") }
        return nil if bos_events.empty? || order_blocks.empty? || atr_values.empty?

        last_bos = bos_events.last
        direction = last_bos[:type] == "bullish_bos" ? "long" : "short"
        matching_obs = order_blocks.select do |ob|
          if direction == "long"
            ob[:type] == "bullish_ob" && ob[:created_at_bos]
          else
            ob[:type] == "bearish_ob" && ob[:created_at_bos]
          end
        end
        return nil if matching_obs.empty?

        ob = matching_obs.last
        atr = atr_values.last || atr_values[-2] || 0
        entry = direction == "long" ? ob[:zone_high] : ob[:zone_low]
        sl = direction == "long" ? ob[:zone_low] - atr * 0.3 : ob[:zone_high] + atr * 0.3
        risk = (entry - sl).abs
        return nil if risk <= 0

        {
          setup: "PB-3 BOS Pullback",
          direction: direction,
          entry: entry.round(2),
          stop_loss: sl.round(2),
          take_profit_1: (entry + risk).round(2),
          take_profit_2: (entry + risk * 2).round(2),
          take_profit_3: (entry + risk * 3).round(2),
          risk_reward_1: 1.0, risk_reward_2: 2.0, risk_reward_3: 3.0,
          order_block_price: ob[:price].round(2),
          bos_price: last_bos[:price]
        }
      end

      # ── Full multi-TF analysis ─────────────────────────────────────────

      def full_timeframe_analysis(candles, interval_label)
        parsed = klines_to_candles(candles)
        return { error: "Not enough klines for #{interval_label}" } if parsed.size < 20

        atr_vals  = compute_atr(parsed)
        pivots    = detect_pivots(parsed)
        structure = analyze_market_structure(parsed, pivots)
        displace  = detect_displacement(parsed, atr_vals)
        obs       = detect_order_blocks(parsed, pivots, displace, atr_vals)
        sweeps    = detect_liquidity_sweeps(parsed, pivots)
        pd       = analyze_pd_array(pivots)
        confirm  = check_entry_confirmation(parsed)
        pb7      = detect_pb7_sweep_ob(parsed, pivots, obs, sweeps, atr_vals)
        pb3      = detect_pb3_bos_pullback(parsed, pivots, obs, structure, atr_vals)

        last_price = parsed.last[:close]
        {
          timeframe: interval_label,
          price: last_price.round(2),
          trend: structure[:trend],
          choch: structure[:choch],
          last_swing_high: structure[:last_swing_high]&.round(2),
          last_swing_low: structure[:last_swing_low]&.round(2),
          protected_high: structure[:protected_high]&.round(2),
          protected_low: structure[:protected_low]&.round(2),
          atr: atr_vals.last&.round(2),
          pivots: { highs: pivots[:highs].last(3).map { |h| h[:price].round(2) },
                    lows: pivots[:lows].last(3).map { |l| l[:price].round(2) } },
          structure_events: structure[:structure].is_a?(Array) ? structure[:structure].last(5) : [],
          displacement: displace.last(3).map { |d| { direction: d[:direction], body: d[:body], atr: d[:atr] } },
          order_blocks: obs.last(5).map { |ob|
            { type: ob[:type], price: ob[:price].round(2), zone: "#{ob[:zone_low].round(2)}–#{ob[:zone_high].round(2)}",
              mitigation: ob[:mitigation], created_at_bos: ob[:created_at_bos] }
          },
          liquidity_sweeps: sweeps.last(3),
          pd_array: pd,
          entry_confirmation: confirm,
          setups: {
            pb7_sweep_ob: pb7 ? { entry: pb7[:entry], sl: pb7[:stop_loss], tp1: pb7[:take_profit_1], rr: "1:3" } : nil,
            pb3_bos_pullback: pb3 ? { entry: pb3[:entry], sl: pb3[:stop_loss], tp1: pb3[:take_profit_1], rr: "1:3" } : nil
          }
        }
      end
    end
  end
end

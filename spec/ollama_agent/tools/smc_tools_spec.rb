# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::SmcAnalysis do
  describe ".klines_to_candles" do
    it "converts raw Binance klines to candle hashes" do
      raw = [[1_700_000_000_000, "50000.0", "51000.0", "49000.0", "50500.0", "100.0"]]
      candles = described_class.klines_to_candles(raw)
      expect(candles.first).to include(time: 1_700_000_000_000, open: 50000.0, high: 51000.0, low: 49000.0, close: 50500.0, volume: 100.0)
    end
  end

  describe ".find_swing_highs" do
    it "finds swing highs with lookback" do
      candles = (1..20).map { |i| { high: 100.0 + rand(10).to_f, low: 90.0 + rand(10).to_f, time: i } }
      candles[5] = { high: 200.0, low: 95.0, time: 5 } # clear swing high
      swings = described_class.find_swing_highs(candles, 2)
      expect(swings).not_to be_empty
    end
  end

  describe ".find_swing_lows" do
    it "finds swing lows with lookback" do
      candles = (1..20).map { |i| { high: 100.0 + rand(10).to_f, low: 90.0 + rand(10).to_f, time: i } }
      candles[5] = { high: 95.0, low: 50.0, time: 5 } # clear swing low
      swings = described_class.find_swing_lows(candles, 2)
      expect(swings).not_to be_empty
    end
  end

  describe ".find_fvgs" do
    it "detects a bullish FVG" do
      candles = [
        { time: 1, open: 100, high: 105, low: 99, close: 104 },
        { time: 2, open: 104, high: 106, low: 100, close: 102 },
        { time: 3, open: 108, high: 112, low: 107, close: 110 }
      ]
      fvgs = described_class.find_fvgs(candles)
      bullish = fvgs.select { |f| f[:type] == "bullish_fvg" }
      expect(bullish).not_to be_empty
    end
  end

  describe ".analyze_trend" do
    it "returns uptrend for rising prices" do
      candles = (1..30).map { |i| { high: 100.0 + i, low: 90.0 + i, close: 95.0 + i } }
      expect(described_class.analyze_trend(candles)).to eq("uptrend")
    end

    it "returns downtrend for falling prices" do
      candles = (1..30).map { |i| { high: 130.0 - i, low: 120.0 - i, close: 125.0 - i } }
      expect(described_class.analyze_trend(candles)).to eq("downtrend")
    end
  end

  describe ".timeframes_for_style" do
    it "returns timeframes for swing trading" do
      tfs = described_class.timeframes_for_style("swing")
      expect(tfs).to eq(entry: "1h", trend: "4h", macro: "1d")
    end

    it "defaults to swing for unknown style" do
      tfs = described_class.timeframes_for_style("unknown")
      expect(tfs).to eq(entry: "1h", trend: "4h", macro: "1d")
    end
  end
end

RSpec.describe OllamaAgent::Tools::FindSmcLevels do
  subject(:tool) { described_class.new }
  let(:mock_klines) do
    (1..100).map do |i|
      base = 50000.0 + (i % 20) * 100
      [1_700_000_000_000 + i * 60_000, (base - 100).to_s, (base + 200).to_s, (base - 200).to_s, (base + 100).to_s, "100.0"]
    end
  end

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return(mock_klines) }

  describe "metadata" do
    it "has the correct name" do
      expect(tool.name).to eq("find_smc_levels")
    end
  end

  describe "#call" do
    it "returns SMC analysis with pivots, OBs, and trend" do
      result = tool.call({ "symbol" => "BTCUSDT", "interval" => "1h" })
      expect(result).to have_key(:symbol)
      expect(result).to have_key(:trend)
      expect(result).to have_key(:pivots)
      expect(result).to have_key(:order_blocks)
      expect(result[:symbol]).to eq("BTCUSDT")
    end
  end
end

RSpec.describe OllamaAgent::Tools::AnalyzeMultiTf do
  subject(:tool) { described_class.new }
  let(:mock_klines) do
    (1..150).map do |i|
      base = 50000.0 + i * 10
      [1_700_000_000_000 + i * 60_000, (base - 50).to_s, (base + 50).to_s, (base - 50).to_s, (base + 25).to_s, "100.0"]
    end
  end

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return(mock_klines) }

  describe "metadata" do
    it "has the correct name" do
      expect(tool.name).to eq("analyze_multi_tf")
    end
  end

  describe "#call" do
    it "returns multi-timeframe analysis with confluence" do
      result = tool.call({ "symbol" => "BTCUSDT", "trading_style" => "swing" })
      expect(result).to have_key(:symbol)
      expect(result).to have_key(:trading_style)
      expect(result).to have_key(:timeframes)
      expect(result).to have_key(:confluence)
      expect(result).to have_key(:bias)
      expect(result[:trading_style]).to eq("swing")
    end
  end
end

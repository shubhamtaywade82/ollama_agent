# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::BinanceTicker do
  subject(:tool) { described_class.new }

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return({ "symbol" => "BTCUSDT", "price" => "50000.00" }) }

  describe "metadata" do
    it "has the correct name" do
      expect(tool.name).to eq("binance_ticker")
    end

    it "is low risk and read_only safe" do
      expect(tool.risk_level).to eq(:low)
      expect(tool.read_only_safe).to be(true)
    end
  end

  describe "#call" do
    it "returns ticker data for a valid symbol" do
      result = tool.call({ "symbol" => "BTCUSDT" })
      expect(result).to include("symbol" => "BTCUSDT", "price" => "50000.00")
    end

    it "upcases the symbol" do
      result = tool.call({ "symbol" => "btcusdt" })
      expect(result).to include("symbol" => "BTCUSDT")
    end

    it "returns error hash when API returns non-hash" do
      allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return("not a hash")
      result = tool.call({ "symbol" => "INVALID" })
      expect(result).to be_a(Hash)
      expect(result).to have_key(:error)
    end

    it "returns error hash when response lacks symbol key" do
      allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return({ "code" => -1121, "msg" => "Invalid symbol" })
      result = tool.call({ "symbol" => "INVALID" })
      expect(result).to have_key(:error)
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceTicker24hr do
  subject(:tool) { described_class.new }

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return({ "symbol" => "BTCUSDT", "priceChange" => "100.0", "priceChangePercent" => "2.0", "lastPrice" => "50000.00", "volume" => "1000.0" }) }

  describe "metadata" do
    it "has the correct name" do
      expect(tool.name).to eq("binance_ticker_24hr")
    end
  end

  describe "#call" do
    it "returns 24hr stats" do
      result = tool.call({ "symbol" => "BTCUSDT" })
      expect(result).to include("symbol" => "BTCUSDT", "priceChangePercent" => "2.0")
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceKlines do
  subject(:tool) { described_class.new }
  let(:mock_klines) do
    [
      [1_700_000_000_000, "50000.0", "51000.0", "49000.0", "50500.0", "100.0", 1_700_003_600_000, "5050000.0", 1000, "50.0", "2500000.0"],
      [1_700_003_600_000, "50500.0", "51500.0", "49500.0", "51000.0", "150.0", 1_700_007_200_000, "7575000.0", 1500, "75.0", "3800000.0"]
    ]
  end

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return(mock_klines) }

  describe "metadata" do
    it "has the correct name" do
      expect(tool.name).to eq("binance_klines")
    end
  end

  describe "#call" do
    it "returns formatted kline array" do
      result = tool.call({ "symbol" => "BTCUSDT", "interval" => "1h", "limit" => 2 })
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result.first).to include(:open, :high, :low, :close, :volume, :trades)
    end

    it "uses default interval and limit" do
      result = tool.call({ "symbol" => "BTCUSDT" })
      expect(result).to be_an(Array)
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceDepth do
  subject(:tool) { described_class.new }

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return({ "bids" => [["50000.0", "1.5"]], "asks" => [["50100.0", "0.8"]] }) }

  describe "#call" do
    it "returns bids and asks" do
      result = tool.call({ "symbol" => "BTCUSDT" })
      expect(result).to have_key("bids")
      expect(result).to have_key("asks")
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceExchangeInfo do
  subject(:tool) { described_class.new }
  let(:mock_info) do
    {
      "timezone" => "UTC",
      "serverTime" => 1_700_000_000_000,
      "symbols" => [
        { "symbol" => "BTCUSDT", "status" => "TRADING", "baseAsset" => "BTC", "quoteAsset" => "USDT", "isSpotTradingAllowed" => true, "filters" => [] },
        { "symbol" => "ETHUSDT", "status" => "TRADING", "baseAsset" => "ETH", "quoteAsset" => "USDT", "isSpotTradingAllowed" => true, "filters" => [] }
      ]
    }
  end

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return(mock_info) }

  describe "#call" do
    it "returns all symbols when no filter given" do
      result = tool.call({})
      expect(result[:symbol_count]).to eq(2)
    end

    it "filters by symbol when provided" do
      result = tool.call({ "symbol" => "BTCUSDT" })
      expect(result[:symbol_count]).to eq(1)
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceFuturesTicker do
  subject(:tool) { described_class.new }

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return({ "symbol" => "BTCUSDT", "price" => "50000.00" }) }

  describe "metadata" do
    it "has the correct name" do
      expect(tool.name).to eq("binance_futures_ticker")
    end
  end

  describe "#call" do
    it "returns futures mark price" do
      result = tool.call({ "symbol" => "BTCUSDT" })
      expect(result).to include("symbol" => "BTCUSDT")
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceFuturesKlines do
  subject(:tool) { described_class.new }

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return([[1_700_000_000_000, "50000.0", "51000.0", "49000.0", "50500.0", "100.0", 1_700_003_600_000, "5050000.0", 1000, "50.0", "2500000.0"]]) }

  describe "#call" do
    it "returns klines" do
      result = tool.call({ "symbol" => "BTCUSDT" })
      expect(result).to be_an(Array)
      expect(result.first).to have_key(:open)
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceFuturesDepth do
  subject(:tool) { described_class.new }

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return({ "bids" => [["50000.0", "1.5"]], "asks" => [["50100.0", "0.8"]] }) }

  describe "#call" do
    it "returns order book" do
      result = tool.call({ "symbol" => "BTCUSDT" })
      expect(result).to have_key("bids")
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceFuturesExchangeInfo do
  subject(:tool) { described_class.new }
  let(:mock_info) do
    {
      "timezone" => "UTC",
      "serverTime" => 1_700_000_000_000,
      "symbols" => [{ "symbol" => "BTCUSDT", "pair" => "BTCUSDT", "contractType" => "PERPETUAL", "status" => "TRADING", "baseAsset" => "BTC", "quoteAsset" => "USDT", "marginAsset" => "USDT", "filters" => [] }]
    }
  end

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return(mock_info) }

  describe "#call" do
    it "returns contract info" do
      result = tool.call({})
      expect(result[:contract_count]).to eq(1)
      expect(result[:symbols].first).to have_key("contractType")
    end
  end
end

RSpec.describe OllamaAgent::Tools::CoinDcxTicker do
  subject(:tool) { described_class.new }
  let(:mock_tickers) do
    [
      { "market" => "BTCUSDT", "last_price" => "50000.0", "change_24_hours" => "2.5" },
      { "market" => "ETHUSDT", "last_price" => "3000.0", "change_24_hours" => "-1.2" }
    ]
  end

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return(mock_tickers) }

  describe "metadata" do
    it "has the correct name" do
      expect(tool.name).to eq("coindcx_ticker")
    end
  end

  describe "#call" do
    it "returns all pairs preview when no symbol given" do
      result = tool.call({})
      expect(result).to have_key(:count)
      expect(result).to have_key(:pairs)
    end

    it "filters by symbol when provided" do
      result = tool.call({ "symbol" => "BTCUSDT" })
      expect(result).to include("market" => "BTCUSDT")
    end

    it "returns error for unknown symbol" do
      result = tool.call({ "symbol" => "INVALID" })
      expect(result).to have_key(:error)
    end
  end
end

RSpec.describe OllamaAgent::Tools::CoinDcxKlines do
  subject(:tool) { described_class.new }
  let(:mock_klines) do
    [{ "time" => 1_700_000_000, "open" => "50000.0", "high" => "51000.0", "low" => "49000.0", "close" => "50500.0", "volume" => "100.0" }]
  end

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return(mock_klines) }

  describe "#call" do
    it "returns klines" do
      result = tool.call({ "symbol" => "BTCUSDT" })
      expect(result).to be_an(Array)
      expect(result.first).to have_key(:time)
    end
  end
end

RSpec.describe OllamaAgent::Tools::CoinDcxDepth do
  subject(:tool) { described_class.new }

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return({ "bids" => [["50000.0", "1.5"]], "asks" => [["50100.0", "0.8"]] }) }

  describe "#call" do
    it "returns depth with truncated bids/asks" do
      result = tool.call({ "symbol" => "BTCUSDT" })
      expect(result).to have_key(:bids)
      expect(result).to have_key(:asks)
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceFundingRate do
  subject(:tool) { described_class.new }
  let(:mock_data) do
    [{ "symbol" => "BTCUSDT", "fundingTime" => 1_700_000_000_000, "fundingRate" => "0.0001", "markPrice" => "50000.0" }]
  end

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return(mock_data) }

  describe "metadata" do
    it "has the correct name" do
      expect(tool.name).to eq("binance_funding_rate")
    end
  end

  describe "#call" do
    it "returns funding rate data" do
      result = tool.call({ "symbol" => "BTCUSDT" })
      expect(result).to be_an(Array)
      expect(result.first).to have_key(:funding_rate)
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceOpenInterest do
  subject(:tool) { described_class.new }

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return({ "symbol" => "BTCUSDT", "openInterest" => "50000.0" }) }

  describe "metadata" do
    it "has the correct name" do
      expect(tool.name).to eq("binance_open_interest")
    end
  end

  describe "#call" do
    it "returns open interest" do
      result = tool.call({ "symbol" => "BTCUSDT" })
      expect(result).to include("symbol" => "BTCUSDT")
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceOpenInterestHist do
  subject(:tool) { described_class.new }
  let(:mock_data) do
    [{ "timestamp" => 1_700_000_000_000, "sumOpenInterest" => "50000.0", "sumOpenInterestValue" => "2500000000.0" }]
  end

  before { allow(OllamaAgent::Tools::CryptoHttp).to receive(:get).and_return(mock_data) }

  describe "#call" do
    it "returns historical OI" do
      result = tool.call({ "symbol" => "BTCUSDT" })
      expect(result).to be_an(Array)
      expect(result.first).to have_key(:sum_open_interest)
    end
  end
end

RSpec.describe OllamaAgent::Tools::CurrentTime do
  subject(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct name" do
      expect(tool.name).to eq("current_time")
    end
  end

  describe "#call" do
    it "returns time hash with UTC, unix, and local" do
      result = tool.call({})
      expect(result).to have_key(:utc)
      expect(result).to have_key(:unix)
      expect(result).to have_key(:local)
      expect(result[:unix]).to be_a(Integer)
    end
  end
end

RSpec.describe OllamaAgent::Tools::CryptoHttp do
  describe ".get" do
    it "returns parsed JSON on success" do
      http_resp = instance_double(Net::HTTPSuccess, code: "200", message: "OK", body: '{"price":"50000"}')
      allow(http_resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request).and_return(http_resp)

      result = described_class.get("https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT")
      expect(result).to eq("price" => "50000")
    end

    it "returns error hash on HTTP failure" do
      http_resp = instance_double(Net::HTTPBadRequest, code: "400", message: "Bad Request")
      allow(http_resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request).and_return(http_resp)

      result = described_class.get("https://api.binance.com/api/v3/ticker/price?symbol=INVALID")
      expect(result).to have_key(:error)
    end

    it "returns error hash on network error" do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      result = described_class.get("https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT")
      expect(result).to have_key(:error)
    end
  end
end

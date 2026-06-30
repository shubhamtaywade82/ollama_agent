# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::BinanceFuturesAuth do
  before do
    @key_was = ENV.delete("BINANCE_API_KEY")
    @secret_was = ENV.delete("BINANCE_API_SECRET")
    ENV["BINANCE_API_KEY"] = "test_key"
    ENV["BINANCE_API_SECRET"] = "test_secret"
  end

  after do
    ENV["BINANCE_API_KEY"] = @key_was
    ENV["BINANCE_API_SECRET"] = @secret_was
  end

  describe "credentials" do
    it "returns true when both are set" do
      expect(described_class.credentials_present?).to be(true)
    end

    it "returns false when missing" do
      ENV.delete("BINANCE_API_KEY")
      expect(described_class.credentials_present?).to be(false)
    end
  end

  describe ".signed_request" do
    it "returns error string when credentials missing" do
      ENV.delete("BINANCE_API_KEY")
      result = described_class.signed_request(:get, "/fapi/v1/ping")
      expect(result).to be_a(String)
      expect(result).to match(/BINANCE_API_KEY/)
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceAccountBalance do
  subject(:tool) { described_class.new }

  before do
    @key_was = ENV.delete("BINANCE_API_KEY")
    @secret_was = ENV.delete("BINANCE_API_SECRET")
    ENV["BINANCE_API_KEY"] = "test_key"
    ENV["BINANCE_API_SECRET"] = "test_secret"
    allow(OllamaAgent::Tools::BinanceFuturesAuth).to receive(:signed_request).and_return({
      "assets" => [{ "asset" => "USDT", "walletBalance" => "10000.0", "availableBalance" => "8000.0", "unrealizedProfit" => "200.0" }]
    })
  end

  after do
    ENV["BINANCE_API_KEY"] = @key_was
    ENV["BINANCE_API_SECRET"] = @secret_was
  end

  describe "metadata" do
    it "has the correct name" do
      expect(tool.name).to eq("binance_account_balance")
    end

    it "is high risk and requires approval" do
      expect(tool.risk_level).to eq(:high)
      expect(tool.requires_approval).to be(true)
    end
  end

  describe "#call" do
    it "returns account balances" do
      result = tool.call({})
      expect(result).to be_an(Array)
      expect(result.first).to include(asset: "USDT", wallet_balance: "10000.0")
    end

    it "returns error when env vars missing" do
      ENV.delete("BINANCE_API_KEY")
      result = tool.call({})
      expect(result).to be_a(String)
      expect(result).to match(/BINANCE_API_KEY/)
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinancePositions do
  subject(:tool) { described_class.new }

  before do
    @key_was = ENV.delete("BINANCE_API_KEY")
    @secret_was = ENV.delete("BINANCE_API_SECRET")
    ENV["BINANCE_API_KEY"] = "test_key"
    ENV["BINANCE_API_SECRET"] = "test_secret"
    allow(OllamaAgent::Tools::BinanceFuturesAuth).to receive(:signed_request).and_return([
      { "symbol" => "BTCUSDT", "positionSide" => "BOTH", "positionAmt" => "0.5", "entryPrice" => "50000.0",
        "markPrice" => "51000.0", "liquidationPrice" => "45000.0", "leverage" => "10",
        "unrealizedProfit" => "500.0", "isolatedMargin" => "2500.0" },
      { "symbol" => "ETHUSDT", "positionSide" => "BOTH", "positionAmt" => "0", "entryPrice" => "0",
        "markPrice" => "3000.0", "liquidationPrice" => "0", "leverage" => "5",
        "unrealizedProfit" => "0", "isolatedMargin" => "0" }
    ])
  end

  after do
    ENV["BINANCE_API_KEY"] = @key_was
    ENV["BINANCE_API_SECRET"] = @secret_was
  end

  describe "#call" do
    it "returns only open positions (non-zero amount)" do
      result = tool.call({})
      expect(result.size).to eq(1)
      expect(result.first).to include(symbol: "BTCUSDT", size: "0.5")
    end

    it "filters by symbol when provided" do
      result = tool.call({ "symbol" => "ETHUSDT" })
      expect(result).to be_empty
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceOpenOrders do
  subject(:tool) { described_class.new }

  before do
    @key_was = ENV.delete("BINANCE_API_KEY")
    @secret_was = ENV.delete("BINANCE_API_SECRET")
    ENV["BINANCE_API_KEY"] = "test_key"
    ENV["BINANCE_API_SECRET"] = "test_secret"
    allow(OllamaAgent::Tools::BinanceFuturesAuth).to receive(:signed_request).and_return([
      { "orderId" => 123, "symbol" => "BTCUSDT", "side" => "BUY", "type" => "LIMIT",
        "price" => "49000.0", "origQty" => "0.1", "executedQty" => "0", "status" => "NEW",
        "stopPrice" => "0", "time" => 1_700_000_000_000 }
    ])
  end

  after do
    ENV["BINANCE_API_KEY"] = @key_was
    ENV["BINANCE_API_SECRET"] = @secret_was
  end

  describe "#call" do
    it "returns open orders" do
      result = tool.call({})
      expect(result).to be_an(Array)
      expect(result.first).to include(order_id: 123, symbol: "BTCUSDT")
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceSetLeverage do
  subject(:tool) { described_class.new }

  before do
    @key_was = ENV.delete("BINANCE_API_KEY")
    @secret_was = ENV.delete("BINANCE_API_SECRET")
    ENV["BINANCE_API_KEY"] = "test_key"
    ENV["BINANCE_API_SECRET"] = "test_secret"
    allow(OllamaAgent::Tools::BinanceFuturesAuth).to receive(:signed_request).and_return({
      "symbol" => "BTCUSDT", "leverage" => 10, "maxNotionalValue" => "500000"
    })
  end

  after do
    ENV["BINANCE_API_KEY"] = @key_was
    ENV["BINANCE_API_SECRET"] = @secret_was
  end

  describe "#call" do
    it "sets leverage and returns result" do
      result = tool.call({ "symbol" => "BTCUSDT", "leverage" => 10 })
      expect(result).to include(leverage: 10)
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinancePlaceOrder do
  subject(:tool) { described_class.new }

  before do
    @key_was = ENV.delete("BINANCE_API_KEY")
    @secret_was = ENV.delete("BINANCE_API_SECRET")
    ENV["BINANCE_API_KEY"] = "test_key"
    ENV["BINANCE_API_SECRET"] = "test_secret"
    allow(OllamaAgent::Tools::BinanceFuturesAuth).to receive(:signed_request).and_return({
      "orderId" => 456, "symbol" => "BTCUSDT", "side" => "BUY", "type" => "MARKET",
      "price" => "50000.0", "origQty" => "0.1", "executedQty" => "0.1", "status" => "FILLED",
      "avgPrice" => "50000.0"
    })
  end

  after do
    ENV["BINANCE_API_KEY"] = @key_was
    ENV["BINANCE_API_SECRET"] = @secret_was
  end

  describe "metadata" do
    it "is critical risk and requires approval" do
      expect(tool.risk_level).to eq(:critical)
      expect(tool.requires_approval).to be(true)
    end
  end

  describe "#call" do
    it "places a market order" do
      result = tool.call({ "symbol" => "BTCUSDT", "side" => "BUY", "type" => "MARKET", "quantity" => "0.1" })
      expect(result).to include(order_id: 456, status: "FILLED")
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceCancelOrder do
  subject(:tool) { described_class.new }

  before do
    @key_was = ENV.delete("BINANCE_API_KEY")
    @secret_was = ENV.delete("BINANCE_API_SECRET")
    ENV["BINANCE_API_KEY"] = "test_key"
    ENV["BINANCE_API_SECRET"] = "test_secret"
    allow(OllamaAgent::Tools::BinanceFuturesAuth).to receive(:signed_request).and_return({
      "symbol" => "BTCUSDT", "orderId" => 123, "origQty" => "0.1"
    })
  end

  after do
    ENV["BINANCE_API_KEY"] = @key_was
    ENV["BINANCE_API_SECRET"] = @secret_was
  end

  describe "#call" do
    it "cancels an order" do
      result = tool.call({ "symbol" => "BTCUSDT", "order_id" => 123 })
      expect(result).to include(status: "cancelled")
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinancePositionSizing do
  subject(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct name" do
      expect(tool.name).to eq("binance_position_sizing")
    end
  end

  describe "#call" do
    it "calculates position size" do
      result = tool.call({ "account_balance" => 10000, "entry_price" => 50000, "stop_price" => 49000, "risk_percent" => 1, "leverage" => 5 })
      expect(result).to include(:position_size_coin, :position_size_usd, :risk_amount_usd, :risk_percent_account)
      expect(result[:leverage]).to eq(5)
    end

    it "warns when risk > 2%" do
      result = tool.call({ "account_balance" => 10000, "entry_price" => 50000, "stop_price" => 40000, "risk_percent" => 15 })
      expect(result[:warning]).to match(/exceeds 2%/)
    end

    it "returns error for invalid entry" do
      result = tool.call({ "account_balance" => 10000, "entry_price" => 0, "stop_price" => 49000 })
      expect(result).to have_key(:error)
    end
  end
end

RSpec.describe OllamaAgent::Tools::BinanceRiskCheck do
  subject(:tool) { described_class.new }

  describe "#call" do
    let(:valid_args) { { "symbol" => "BTCUSDT", "side" => "BUY", "entry_price" => 50000, "stop_price" => 49000, "quantity" => 0.1, "account_balance" => 10000 } }

    it "passes safe trades" do
      result = tool.call(valid_args)
      expect(result[:passed]).to be(true)
    end

    it "flags risk > 2%" do
      result = tool.call(valid_args.merge("quantity" => 5, "entry_price" => 50000))
      expect(result[:passed]).to be(false)
      expect(result[:warnings]).to be_an(Array)
      expect(result[:warnings].first).to match(/RISK_EXCEEDS_2PCT/)
    end

    it "flags tight stops" do
      result = tool.call(valid_args.merge("stop_price" => 49900))
      expect(result[:passed]).to be(false)
      expect(result[:warnings]).to be_an(Array)
      expect(result[:warnings].first).to match(/STOP_TOO_TIGHT/)
    end

    it "returns error for invalid side" do
      result = tool.call(valid_args.merge("side" => "INVALID"))
      expect(result).to have_key(:error)
    end
  end
end

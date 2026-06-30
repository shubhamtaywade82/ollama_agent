# frozen_string_literal: true

require "cgi"
require "net/http"
require "json"
require "openssl"
require "uri"

require_relative "base"
require_relative "enhanced_registry"
require_relative "crypto_tools"

module OllamaAgent
  module Tools
    # ── CoinDCX authenticated request helper ────────────────────────────
    module CoinDcxAuth
      module_function

      API_BASE = "https://api.coindcx.com"

      def api_key
        ENV.fetch("COINDCX_API_KEY", nil)
      end

      def api_secret
        ENV.fetch("COINDCX_API_SECRET", nil)
      end

      def credentials_present?
        !!(api_key && !api_key.empty? && api_secret && !api_secret.empty?)
      end

      def missing_credentials_error
        "Error: COINDCX_API_KEY and COINDCX_API_SECRET must be set"
      end

      def signed_get(path, params = {})
        return missing_credentials_error unless credentials_present?

        query = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
        payload = query.empty? ? "" : query
        signature = OpenSSL::HMAC.hexdigest("SHA256", api_secret, payload)
        uri_str = "#{API_BASE}#{path}#{query.empty? ? '' : '?'}#{query}"
        uri = URI(uri_str)

        Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 15, open_timeout: 10) do |http|
          req = Net::HTTP::Get.new(uri)
          req["X-AUTH-APIKEY"] = api_key
          req["X-AUTH-SIGNATURE"] = signature
          resp = http.request(req)
          raise "HTTP #{resp.code}: #{resp.body[0, 200]}" unless resp.is_a?(Net::HTTPSuccess)
          JSON.parse(resp.body)
        end
      rescue JSON::ParserError
        { error: "Invalid JSON from CoinDCX" }
      rescue StandardError => e
        { error: e.message }
      end

      def signed_post(path, body_data = {})
        return missing_credentials_error unless credentials_present?

        json_body = JSON.generate(body_data)
        signature = OpenSSL::HMAC.hexdigest("SHA256", api_secret, json_body)
        uri = URI("#{API_BASE}#{path}")

        Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 15, open_timeout: 10) do |http|
          req = Net::HTTP::Post.new(uri)
          req["X-AUTH-APIKEY"] = api_key
          req["X-AUTH-SIGNATURE"] = signature
          req["Content-Type"] = "application/json"
          req.body = json_body
          resp = http.request(req)
          raise "HTTP #{resp.code}: #{resp.body[0, 200]}" unless resp.is_a?(Net::HTTPSuccess)
          JSON.parse(resp.body)
        end
      rescue JSON::ParserError
        { error: "Invalid JSON from CoinDCX" }
      rescue StandardError => e
        { error: e.message }
      end
    end

    # ── CoinDCX Account Tools ────────────────────────────────────────────

    class CoinDcxGetBalance < Base
      tool_name        "coindcx_get_balance"
      tool_description "Get CoinDCX account balances for all assets. Requires COINDCX_API_KEY and COINDCX_API_SECRET."
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object", properties: {}, required: []
                  })

      def call(_args, _context = {})
        return CoinDcxAuth.missing_credentials_error unless CoinDcxAuth.credentials_present?

        data = CoinDcxAuth.signed_get("/api/v3/account/balance")
        return data if data.is_a?(Hash) && data.key?("error")

        balances = data.is_a?(Array) ? data : (data["balances"] || [])
        balances.map { |b| { asset: b["asset"] || b["currency"], balance: b["balance"] || b["available_balance"], locked: b["locked"] || "0" } }
      rescue StandardError => e
        "Error fetching CoinDCX balance: #{e.message}"
      end
    end

    class CoinDcxGetPositions < Base
      tool_name        "coindcx_get_positions"
      tool_description "Get CoinDCX open positions with entry price, PnL, and quantity. Requires COINDCX_API_KEY and COINDCX_API_SECRET."
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object", properties: {}, required: []
                  })

      def call(_args, _context = {})
        return CoinDcxAuth.missing_credentials_error unless CoinDcxAuth.credentials_present?

        data = CoinDcxAuth.signed_get("/api/v3/account/positions")
        return data if data.is_a?(Hash) && data.key?("error")

        positions = data.is_a?(Array) ? data : (data["positions"] || [])
        positions.select { |p| (p["quantity"] || p["size"] || "0").to_f != 0 }.map do |p|
          {
            symbol: p["symbol"] || p["market"],
            side: p["side"] || (p["quantity"].to_f > 0 ? "long" : "short"),
            quantity: p["quantity"] || p["size"],
            entry_price: p["entry_price"] || p["avg_price"],
            mark_price: p["mark_price"] || p["current_price"],
            unrealized_pnl: p["unrealized_pnl"] || p["pnl"]
          }
        end
      rescue StandardError => e
        "Error fetching CoinDCX positions: #{e.message}"
      end
    end

    class CoinDcxGetOpenOrders < Base
      tool_name        "coindcx_get_open_orders"
      tool_description "Get CoinDCX pending orders. Use to find order IDs for cancellation."
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Optional trading pair, e.g. BTCUSDT" }
                    },
                    required: []
                  })

      def call(args, _context = {})
        return CoinDcxAuth.missing_credentials_error unless CoinDcxAuth.credentials_present?

        params = {}
        params[:market] = args["symbol"].to_s.strip.upcase if args["symbol"]
        data = CoinDcxAuth.signed_get("/api/v3/orders/open", params)
        return data if data.is_a?(Hash) && data.key?("error")

        orders = data.is_a?(Array) ? data : (data["orders"] || [])
        orders.map do |o|
          {
            id: o["id"] || o["order_id"],
            symbol: o["market"] || o["symbol"], side: o["side"],
            type: o["order_type"] || o["type"], price: o["price"],
            quantity: o["quantity"] || o["total_quantity"],
            executed: o["executed_quantity"] || o["filled_quantity"],
            status: o["status"]
          }
        end
      rescue StandardError => e
        "Error fetching CoinDCX open orders: #{e.message}"
      end
    end

    # ── CoinDCX Execution Tools ──────────────────────────────────────────

    class CoinDcxPlaceOrder < Base
      tool_name        "coindcx_place_order"
      tool_description "Place a market or limit order on CoinDCX. Preferred over Binance for execution. Always present trade details to user for confirmation before calling."
      tool_risk        :critical
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      symbol:   { type: "string", description: "Trading pair, e.g. BTCUSDT" },
                      side:     { type: "string", description: "buy or sell", enum: %w[buy sell] },
                      type:     { type: "string", description: "market or limit", default: "market" },
                      quantity: { type: "string", description: "Order quantity in coin, e.g. 0.001" },
                      price:    { type: "string", description: "Limit price (required for limit orders)" }
                    },
                    required: %w[symbol side quantity]
                  })

      def call(args, _context = {})
        return CoinDcxAuth.missing_credentials_error unless CoinDcxAuth.credentials_present?

        body = {
          market: args["symbol"].to_s.strip.upcase,
          side: args["side"].to_s.strip.downcase,
          order_type: args.fetch("type", "market").to_s.strip.downcase,
          quantity: args["quantity"].to_s
        }
        body[:price] = args["price"].to_s if args["price"] && !args["price"].to_s.empty?

        data = CoinDcxAuth.signed_post("/api/v3/orders/create", body)
        return data if data.is_a?(Hash) && data.key?("error")

        {
          id: data["id"] || data["order_id"],
          symbol: body[:market], side: body[:side],
          type: body[:order_type], quantity: body[:quantity],
          price: body[:price],
          status: data["status"] || "submitted"
        }
      rescue StandardError => e
        "Error placing CoinDCX order: #{e.message}"
      end
    end

    class CoinDcxCancelOrder < Base
      tool_name        "coindcx_cancel_order"
      tool_description "Cancel an open order on CoinDCX by order ID."
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      id: { type: "string", description: "Order ID from open orders list" }
                    },
                    required: ["id"]
                  })

      def call(args, _context = {})
        return CoinDcxAuth.missing_credentials_error unless CoinDcxAuth.credentials_present?

        data = CoinDcxAuth.signed_post("/api/v3/orders/cancel", { id: args["id"].to_s })
        return data if data.is_a?(Hash) && data.key?("error")

        { status: "cancelled", id: args["id"].to_s }
      rescue StandardError => e
        "Error cancelling CoinDCX order: #{e.message}"
      end
    end

    # ── Registrations ───────────────────────────────────────────────────────

    EnhancedRegistry.register(CoinDcxGetBalance)
    EnhancedRegistry.register(CoinDcxGetPositions)
    EnhancedRegistry.register(CoinDcxGetOpenOrders)
    EnhancedRegistry.register(CoinDcxPlaceOrder)
    EnhancedRegistry.register(CoinDcxCancelOrder)
  end
end

# frozen_string_literal: true

require_relative "../base"

module TradingAgent
  module Exchanges
    module Binance
      # Binance USD-M Futures adapter. Wraps the `binance-connector-ruby` gem for REST
      # (orders / positions / leverage / account) and delegates streaming to
      # {WebsocketClient} + {StreamManager}.
      #
      # Phase 1 work: implement these against the SDK and verify on TESTNET.
      class FuturesClient < Exchanges::Base
        REST_MAINNET = "https://fapi.binance.com"
        REST_TESTNET = "https://testnet.binancefuture.com"

        def initialize(config: TradingAgent.configuration)
          super()
          @config = config
        end

        def place_order(symbol:, side:, type:, quantity:, client_order_id:, price: nil)
          # TODO(phase1): rest_client.new_order(symbol:, side:, type:, quantity:,
          #   newClientOrderId: client_order_id, price:) — client_order_id is the idempotency key.
          raise NotImplementedError, "FuturesClient#place_order (phase 1)"
        end

        def cancel_order(symbol:, order_id:)
          raise NotImplementedError, "FuturesClient#cancel_order (phase 1)"
        end

        def positions
          raise NotImplementedError, "FuturesClient#positions (phase 1)"
        end

        def balances
          raise NotImplementedError, "FuturesClient#balances (phase 1)"
        end

        def set_leverage(symbol:, leverage:)
          raise NotImplementedError, "FuturesClient#set_leverage (phase 1)"
        end

        def subscribe_market(symbol:, &on_event)
          stream_manager.subscribe_market(symbol: symbol, &on_event)
        end

        def subscribe_user(&on_event)
          stream_manager.subscribe_user(&on_event)
        end

        private

        def rest_base_url
          @config.base_url || (@config.testnet ? REST_TESTNET : REST_MAINNET)
        end

        # Lazily constructed so `require "trading_agent"` works without the SDK installed.
        def rest_client
          @rest_client ||= begin
            require "binance"
            ::Binance::Spot # placeholder; replace with the futures client class in phase 1
          end
        end

        def stream_manager
          @stream_manager ||= StreamManager.new(config: @config)
        end
      end
    end
  end
end

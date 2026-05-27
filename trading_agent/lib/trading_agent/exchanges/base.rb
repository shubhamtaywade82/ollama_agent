# frozen_string_literal: true

module TradingAgent
  module Exchanges
    # Abstract exchange adapter contract. Concrete adapters (Binance, Bybit, Dhan, Zerodha...)
    # implement these methods so the runtime never depends on a specific exchange SDK.
    #
    # This is the ONLY layer permitted to talk to an exchange.
    class Base
      def place_order(symbol:, side:, type:, quantity:, client_order_id:, price: nil)
        raise NotImplementedError, "#{self.class}#place_order"
      end

      def cancel_order(symbol:, order_id:)
        raise NotImplementedError, "#{self.class}#cancel_order"
      end

      # @return [Array<Hash>] open positions
      def positions
        raise NotImplementedError, "#{self.class}#positions"
      end

      # @return [Hash] balances by asset
      def balances
        raise NotImplementedError, "#{self.class}#balances"
      end

      def set_leverage(symbol:, leverage:)
        raise NotImplementedError, "#{self.class}#set_leverage"
      end

      # Subscribe to the public market stream (aggTrade/kline/depth).
      def subscribe_market(symbol:, &on_event)
        raise NotImplementedError, "#{self.class}#subscribe_market"
      end

      # Subscribe to the authenticated user-data stream (fills, balance, position updates).
      def subscribe_user(&on_event)
        raise NotImplementedError, "#{self.class}#subscribe_user"
      end
    end
  end
end

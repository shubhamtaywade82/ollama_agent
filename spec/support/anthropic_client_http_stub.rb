# frozen_string_literal: true

module OllamaAgent
  module AnthropicClientSpec
    # Test double for +Net::HTTP+ constructor + request + timeout hooks.
    class HttpStub
      class << self
        attr_accessor :response, :instances
      end

      def initialize(_hostname, _port_number)
        (self.class.instances ||= []) << self
      end

      def use_ssl=(flag)
        flag
      end

      def open_timeout=(seconds)
        seconds
      end

      def read_timeout=(seconds)
        seconds
      end

      def request(_req)
        self.class.response
      end
    end
  end
end

# frozen_string_literal: true

module Outer
  class Inner
    def instance_method
      :ok
    end

    def self.singleton_method
      :ok
    end

    class << self
      def meta
        :meta
      end
    end
  end
end

def top_level_method
  :top
end

# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # Monotonic logical stamps for orchestration (no wall clock / Time.now).
    class LogicalClock
      def initialize(epoch: 0)
        @epoch = epoch.to_i
        @sequence = 0
        @mutex = Mutex.new
      end

      # @return [String] next logical stamp, e.g. "0:1".
      def next_stamp
        @mutex.synchronize do
          @sequence += 1
          "#{@epoch}:#{@sequence}"
        end
      end
    end
  end
end

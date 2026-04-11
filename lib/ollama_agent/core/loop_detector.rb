# frozen_string_literal: true

module OllamaAgent
  module Core
    # Detects when the agent is stuck in a repeating tool-call loop.
    #
    # Strategy: keep a sliding window of (tool_name + args_fingerprint) tokens.
    # If the most-recent window pattern appears THRESHOLD or more times in the
    # accumulated history, we declare a loop.
    class LoopDetector
      DEFAULT_WINDOW    = 4   # number of consecutive calls to treat as one pattern
      DEFAULT_THRESHOLD = 2   # how many times the pattern must repeat

      attr_reader :history

      def initialize(window: DEFAULT_WINDOW, threshold: DEFAULT_THRESHOLD)
        @window    = window.to_i.clamp(1, 32)
        @threshold = threshold.to_i.clamp(2, 16)
        @history   = []
      end

      # Record a tool call. Should be called before executing each tool.
      # @param tool_name [String]
      # @param args [Hash, String]
      def record!(tool_name, args = {})
        @history << fingerprint(tool_name, args)
      end

      # Returns true when the recent pattern has repeated enough times.
      def loop_detected?
        return false if @history.size < @window * @threshold

        pattern = @history.last(@window)
        matches = 0

        (@history.size - @window + 1).times do |i|
          matches += 1 if @history[i, @window] == pattern
        end

        matches >= @threshold
      end

      # Human-readable description of the detected loop.
      def loop_summary
        return nil unless loop_detected?

        pattern = @history.last(@window)
        "Loop detected: pattern [#{pattern.join(" → ")}] repeated #{@threshold}+ times"
      end

      def reset!
        @history.clear
      end

      private

      def fingerprint(tool_name, args)
        stable = case args
                 when Hash  then args.sort.map { |k, v| "#{k}=#{v}" }.join(",")
                 when Array then args.map(&:to_s).join(",")
                 else        args.to_s
                 end
        "#{tool_name}(#{stable[0, 80]})"
      end
    end
  end
end

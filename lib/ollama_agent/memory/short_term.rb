# frozen_string_literal: true

module OllamaAgent
  module Memory
    # In-memory sliding window of recent tool calls and observations.
    # Cleared at the end of each run. Never persisted.
    class ShortTerm
      DEFAULT_MAX_ENTRIES = 20

      Entry = Data.define(:type, :content, :ts)

      attr_reader :entries

      def initialize(max: DEFAULT_MAX_ENTRIES)
        @max     = max
        @entries = []
      end

      # Record a new entry.
      # @param type    [Symbol]  :tool_call, :tool_result, :observation, :reasoning
      # @param content [Object]  anything serialisable
      def record(type, content)
        @entries << Entry.new(type: type.to_sym, content: content, ts: Time.now.to_f)
        @entries.shift if @entries.size > @max
        nil
      end

      # Return the N most recent entries.
      def recent(n = 5)
        @entries.last(n)
      end

      # Return all entries of a given type.
      def by_type(type)
        @entries.select { |e| e.type == type.to_sym }
      end

      # Last N tool calls (name + args)
      def recent_tool_calls(n = 5)
        by_type(:tool_call).last(n)
      end

      # True if the same tool+args was called recently (loop hint).
      def recently_called?(tool_name, args, window: 6)
        recent(window).any? do |e|
          e.type == :tool_call &&
            e.content[:tool] == tool_name.to_s &&
            e.content[:args].to_s == args.to_s
        end
      end

      def size
        @entries.size
      end

      def clear!
        @entries.clear
        nil
      end

      def to_a
        @entries.map(&:to_h)
      end
    end
  end
end

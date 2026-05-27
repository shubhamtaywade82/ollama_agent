# frozen_string_literal: true

module OllamaAgent
  module ToolRuntime
    # Phase-scoped tool visibility (planning vs mutation vs verification vs integration).
    class ToolRegistry
      PHASES = %i[planning mutation verification integration].freeze

      def initialize
        @entries = {}
      end

      def register(name:, callable:, phases:)
        raise ArgumentError, "callable must respond to #call" unless callable.respond_to?(:call)

        key = name.to_s
        raise ArgumentError, "duplicate tool name: #{key}" if @entries.key?(key)

        list = Array(phases).map(&:to_sym)
        list.each { |ph| validate_phase!(ph) }
        @entries[key] = { callable: callable, phases: list }
      end

      def available_in(phase:)
        ph = phase.to_sym
        validate_phase!(ph)
        @entries.filter_map do |name, meta|
          next unless meta[:phases].include?(ph)

          { name: name, callable: meta[:callable] }
        end
      end

      def invoke(name:, phase:, **args)
        ph = phase.to_sym
        validate_phase!(ph)
        entry = @entries[name.to_s]
        return :tool_not_available_in_phase unless entry && entry[:phases].include?(ph)

        entry[:callable].call(**args)
      end

      private

      def validate_phase!(phase)
        return if PHASES.include?(phase)

        raise ArgumentError, "unknown phase #{phase.inspect}"
      end
    end
  end
end

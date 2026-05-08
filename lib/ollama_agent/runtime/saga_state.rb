# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # Finite state labels and legal edges for {SagaCoordinator}.
    module SagaState
      STATES = %w[
        reserved
        locked
        mutations_applied
        verified
        integration_queued
        committed
        compensated
      ].freeze

      TERMINAL = %w[committed compensated].freeze

      ALLOWED = {
        "reserved" => %w[locked compensated],
        "locked" => %w[mutations_applied compensated],
        "mutations_applied" => %w[verified compensated],
        "verified" => %w[integration_queued compensated],
        "integration_queued" => %w[committed compensated]
      }.freeze

      module_function

      # @param from [#to_s]
      # @param to [#to_s]
      def can_transition?(from, to)
        key = from.to_s
        return false unless ALLOWED.key?(key)

        ALLOWED[key].include?(to.to_s)
      end

      # @param state [#to_s]
      def terminal?(state)
        TERMINAL.include?(state.to_s)
      end
    end
  end
end

# frozen_string_literal: true

require_relative "execution_mode"

module OllamaAgent
  module Runtime
    # Gates mutations by ownership node criticality and mode.
    module CriticalityPolicy
      class << self
        # Optional proc called as audit_listener.call(node:, mode:) for +sensitive+ branches.
        attr_accessor :audit_listener

        # @return [:allow, :require_supervisor_lease, :reject]
        def gate(node, mode:)
          mode_s = mode.to_s
          return :reject unless gateable?(node, mode_s)

          criticality_result(node, mode_s)
        end

        private

        def gateable?(node, mode_s)
          return false unless node && !node.forbidden
          return true if node.mutable_in_modes.include?(mode_s)
          return true if mode_s == "shadow" && node.mutable_in_modes.include?(ExecutionMode::NORMAL)

          false
        end

        def criticality_result(node, mode_s)
          case node.criticality
          when "routine"
            :allow
          when "sensitive"
            allow_sensitive(node, mode_s)
          when "critical"
            :require_supervisor_lease
          else
            :reject
          end
        end

        def allow_sensitive(node, mode_s)
          audit_listener&.call(node: node, mode: mode_s)
          :allow
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative "../runtime/execution_mode"

module OllamaAgent
  module Security
    # Raised when owners.yml fails structural or policy validation.
    class OwnershipCompileError < StandardError; end

    # Validates flattened ownership rule rows produced during compile.
    class OwnershipCompileValidators
      CRITICALITIES = %w[routine sensitive critical].freeze

      def self.validate!(flat)
        new.validate!(flat)
      end

      def validate!(flat)
        validate_duplicate_prefixes!(flat)
        validate_modes_and_criticality!(flat)
        validate_privilege_restriction!(flat)
      end

      private

      def validate_duplicate_prefixes!(flat)
        seen = {}
        flat.each do |row|
          prefix = row[:prefix]
          raise OwnershipCompileError, "duplicate prefix: #{prefix}" if seen[prefix]

          seen[prefix] = true
        end
      end

      def validate_privilege_restriction!(flat)
        flat.each do |row|
          next if privilege_ok?(row)

          raise OwnershipCompileError, privilege_violation_message(row)
        end
      end

      def privilege_ok?(row)
        row[:mutable_in_modes].all? { |mode| row[:parent_modes].include?(mode) }
      end

      def privilege_violation_message(row)
        child_modes = row[:mutable_in_modes]
        parent_modes = row[:parent_modes]
        "privilege escalation: #{row[:prefix]} mutable_in_modes must be subset of parent's " \
          "(#{child_modes} vs #{parent_modes})"
      end

      def validate_modes_and_criticality!(flat)
        flat.each do |row|
          validate_modes_for_prefix!(row)
          validate_criticality_for_prefix!(row)
        end
      end

      def validate_modes_for_prefix!(row)
        row[:mutable_in_modes].each do |mode|
          next if OllamaAgent::Runtime::ExecutionMode.valid?(mode)

          raise OwnershipCompileError, "invalid mutable_in_modes entry #{mode.inspect} at #{row[:prefix]}"
        end
      end

      def validate_criticality_for_prefix!(row)
        return if CRITICALITIES.include?(row[:criticality])

        raise OwnershipCompileError, "invalid criticality #{row[:criticality].inspect} at #{row[:prefix]}"
      end
    end
  end
end

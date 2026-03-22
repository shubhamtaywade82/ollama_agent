# frozen_string_literal: true

module OllamaAgent
  module RubyIndex
    # Builds a stable "A::B::C" string from Prism constant path nodes.
    module Naming
      module_function

      # rubocop:disable Metrics/MethodLength -- Prism node shape dispatch
      def full_constant_path(node)
        case node
        when nil
          nil
        when Prism::ConstantReadNode
          node.name.to_s
        when Prism::ConstantPathNode
          parent = full_constant_path(node.parent)
          name = node.name.to_s
          parent ? "#{parent}::#{name}" : name
        when Prism::ConstantPathShellNode
          full_constant_path(node.name)
        end
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end

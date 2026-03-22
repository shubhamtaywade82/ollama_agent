# frozen_string_literal: true

require "prism"

require_relative "naming"

module OllamaAgent
  module RubyIndex
    # Walks a Prism AST and collects class, module, and method definitions.
    class ExtractorVisitor < Prism::Visitor
      attr_reader :constants, :methods

      def initialize(relative_path)
        super()
        @relative_path = relative_path
        @scope = []
        @singleton_class_depth = 0
        @constants = []
        @methods = []
      end

      def visit_module_node(node)
        segment = Naming.full_constant_path(node.constant_path)
        @scope.push(segment) if segment && !segment.empty?
        record_constant(:module, node)
        super
        @scope.pop if segment && !segment.empty?
      end

      def visit_class_node(node)
        segment = Naming.full_constant_path(node.constant_path)
        @scope.push(segment) if segment && !segment.empty?
        record_constant(:class, node)
        super
        @scope.pop if segment && !segment.empty?
      end

      def visit_singleton_class_node(node)
        @singleton_class_depth += 1
        super
        @singleton_class_depth -= 1
      end

      def visit_def_node(node)
        record_method(node)
        super
      end

      private

      def current_namespace
        @scope.empty? ? "" : @scope.join("::")
      end

      def record_constant(kind, node)
        qualified = current_namespace
        loc = node.location
        @constants << {
          kind: kind,
          name: qualified,
          path: @relative_path,
          start_line: loc.start_line,
          end_line: loc.end_line
        }
      end

      def record_method(node)
        loc = node.location
        singleton = !node.receiver.nil? || @singleton_class_depth.positive?
        @methods << {
          name: node.name.to_s,
          path: @relative_path,
          start_line: loc.start_line,
          end_line: loc.end_line,
          namespace: current_namespace,
          singleton: singleton
        }
      end
    end
  end
end

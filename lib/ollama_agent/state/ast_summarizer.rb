# frozen_string_literal: true

require "prism"

module OllamaAgent
  module State
    # Prism-based structural summaries for re-entry packets (bounded semantic context).
    class ASTSummarizer
      def initialize(workspace_root:)
        @workspace_root = workspace_root.to_s
      end

      def summarize(file_paths:, touched_methods: [])
        touched = Array(touched_methods).map(&:to_s).uniq
        files = {}
        Array(file_paths).each do |raw_path|
          rel = relativize(raw_path)
          files[rel] = summarize_one(rel, touched)
        end
        { files: files }
      end

      private

      def relativize(path)
        abs = File.expand_path(path.to_s)
        root = File.expand_path(@workspace_root)
        return abs.delete_prefix("#{root}/") if abs.start_with?("#{root}/")

        path.to_s
      end

      def summarize_one(relative_path, touched)
        absolute_path = File.join(@workspace_root, relative_path)
        return "parse_error" unless File.file?(absolute_path)

        source = File.read(absolute_path)
        parsed = Prism.parse(source, filepath: absolute_path)
        return "parse_error" if parsed.failure?

        visitor = SummaryVisitor.new(source, touched)
        parsed.value.accept(visitor)
        visitor.to_summary
      rescue StandardError
        "parse_error"
      end

      # Walks a single compilation unit and builds the summary payload.
      class SummaryVisitor < Prism::Visitor
        def initialize(source, touched)
          super()
          @source = source
          @touched = touched
          @requires = []
          @constants = []
          @scope_methods = Hash.new { |h, k| h[k] = [] }
          @touched_bodies = {}
          @class_stack = ["(main)"]
          @scope_methods["(main)"] = []
        end

        def visit_module_node(node)
          push_scope(module_name(node))
          super
          pop_scope
        end

        def visit_class_node(node)
          push_scope(class_name(node))
          super
          pop_scope
        end

        def visit_def_node(node)
          record_method(node)
          super
        end

        def visit_call_node(node)
          capture_require(node)
          super
        end

        def visit_constant_write_node(node)
          @constants << node.name.to_s
          super
        end

        def to_summary
          {
            classes: classes_payload,
            constants: @constants.uniq.sort,
            requires: @requires.compact.uniq.sort,
            touched_method_bodies: @touched_bodies
          }
        end

        private

        def classes_payload
          entries = @scope_methods.map do |name, methods|
            { name: name, methods: methods.uniq.sort }
          end
          entries.sort_by { |c| c[:name] }
        end

        def module_name(node)
          OllamaAgent::RubyIndex::Naming.full_constant_path(node.constant_path).to_s
        end

        def class_name(node)
          OllamaAgent::RubyIndex::Naming.full_constant_path(node.constant_path).to_s
        end

        def push_scope(name)
          @class_stack.push(name)
          @scope_methods[name] ||= []
        end

        def pop_scope
          @class_stack.pop
        end

        def current_scope
          @class_stack.last
        end

        def record_method(node)
          entry = method_label(node)
          list = @scope_methods[current_scope]
          list << entry unless list.include?(entry)

          return unless body_wanted?(node)

          @touched_bodies[node.name.to_s] = slice_location(node.location)
        end

        def method_label(node)
          return "self.#{node.name}" if node.receiver

          node.name.to_s
        end

        def body_wanted?(node)
          n = node.name.to_s
          @touched.include?(n) || @touched.include?("self.#{n}")
        end

        def slice_location(loc)
          @source.byteslice(loc.start_offset, loc.length)
        end

        def capture_require(node)
          return unless node.receiver.nil? && %i[require require_relative].include?(node.name)

          args = node.arguments&.arguments
          return unless args.is_a?(Array)

          first = args.first
          return unless first.is_a?(Prism::StringNode)

          @requires << first.unescaped
        end
      end
    end
  end
end

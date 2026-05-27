# frozen_string_literal: true

require "prism"

require_relative "concern_body"
require_relative "semantic_context"

module OllamaAgent
  module Topology
    module Extractors
      # Reopened in this file — see +ruby_semantic_extractor.rb+ for the superclass.
      class RubySemanticExtractor
        # Class/module scope stack and Prism visit entry points.
        module Navigation
          def visit_class_node(node)
            open_scope(node, :class) { super }
          end

          def visit_module_node(node)
            open_scope(node, :module) { super }
          end

          def visit_def_node(node)
            record_method_definition(node)
            super
          end

          def visit_call_node(node)
            if class_methods_block?(node)
              around_class_methods_block { super }
              return
            end

            handle_include_extend(node)
            handle_before_action(node)
            super
          end

          private

          def open_scope(node, kind)
            ctx = scope_context_for(node, kind)
            enter_scope(ctx[:fqcn], ctx)
            yield
            emit_scope_ir(ctx, node.body, kind)
          ensure
            leave_scope
          end

          def scope_context_for(node, kind)
            fqcn = compose_fqcn(node)
            SemanticContext.build(
              kind: kind,
              fqcn: fqcn,
              module_chain: @namespace_stack.dup,
              superclass_fqcn: (kind == :class ? superclass_fqcn(node.superclass) : nil),
              line: node.location.start_line
            )
          end

          def enter_scope(fqcn, ctx)
            @namespace_stack << fqcn
            @context_stack.push(ctx)
          end

          def leave_scope
            @context_stack.pop
            @namespace_stack.pop
          end

          def emit_scope_ir(ctx, body, kind)
            if ConcernBody.concern?(body)
              emit_concern(ctx)
              return
            end

            if kind == :class
              emit_worker_if_needed(ctx)
              emit_class(ctx)
            else
              emit_module(ctx)
            end
          end

          def record_method_definition(node)
            ctx = @context_stack.last
            return unless ctx

            ctx[:methods] << method_entry(node)
            if ctx[:in_class_methods_block].positive?
              ctx[:class_method_names] << node.name.to_s
            else
              ctx[:instance_method_names] << node.name.to_s
            end
          end

          def class_methods_block?(node)
            node.name == :class_methods && node.block && @context_stack.last
          end

          def around_class_methods_block
            ctx = @context_stack.last
            ctx[:in_class_methods_block] += 1
            begin
              yield
            ensure
              ctx[:in_class_methods_block] -= 1
            end
          end

          def compose_fqcn(node)
            path = qualified_name(node.constant_path)
            return path if path.include?("::")
            return path if @namespace_stack.empty?

            "#{@namespace_stack.join("::")}::#{path}"
          end
        end

        include Navigation
      end
    end
  end
end

# frozen_string_literal: true

require "prism"

require_relative "../../../ruby_index/naming"
require_relative "../../ir/callback_node"

module OllamaAgent
  module Topology
    module Extractors
      # Reopened in this file — see +ruby_semantic_extractor.rb+ for the superclass.
      class RubySemanticExtractor
        # Include/extend hooks, Rails-ish callbacks, and method shape capture.
        module MixinDispatch
          private

          def handle_include_extend(node)
            ctx = mixin_context(node)
            return unless ctx

            mod_fqcn = mixin_fqcn(node)
            return unless mod_fqcn

            node.name == :include ? apply_include(ctx, fqcn: mod_fqcn) : apply_extend(ctx, fqcn: mod_fqcn)
          end

          def mixin_context(node)
            last = @context_stack.last
            return unless last
            return unless node.receiver.nil? && %i[include extend].include?(node.name)

            last
          end

          def mixin_fqcn(node)
            OllamaAgent::RubyIndex::Naming.full_constant_path(node.arguments&.arguments&.first)&.to_s
          end

          def apply_include(ctx, fqcn:)
            ctx[:includes] << fqcn
            ctx[:sidekiq_worker] = true if fqcn.include?("Sidekiq::Worker")
          end

          def apply_extend(ctx, fqcn:)
            ctx[:extends] << fqcn
          end

          def handle_before_action(node)
            ctx = @context_stack.last
            return unless ctx && ctx[:kind] == :class
            return unless node.name == :before_action && node.receiver.nil?

            enqueue_before_action(ctx, node)
          end

          def enqueue_before_action(ctx, node)
            meth = callback_method_name(node)
            return unless meth

            @pending << IR::CallbackNode.build(
              source_path: @file_path,
              source_line: node.location.start_line,
              origin_extractor_version: EXTRACTOR_VERSION,
              owner_fqcn: ctx[:fqcn],
              phase: "before_action",
              method_name: meth
            )
          end

          def callback_method_name(node)
            arg = node.arguments&.arguments&.first
            case arg
            when Prism::SymbolNode, Prism::StringNode
              arg.unescaped
            end
          end

          def qualified_name(constant_path)
            OllamaAgent::RubyIndex::Naming.full_constant_path(constant_path).to_s
          end

          def superclass_fqcn(super_node)
            return nil unless super_node

            OllamaAgent::RubyIndex::Naming.full_constant_path(super_node).to_s
          end

          def method_entry(node)
            {
              name: node.name.to_s,
              kind: node.receiver ? "singleton" : "instance",
              parameters: ParameterList.build(node.parameters)
            }
          end
        end

        include MixinDispatch
      end
    end
  end
end

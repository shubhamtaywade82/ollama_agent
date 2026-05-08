# frozen_string_literal: true

require_relative "../ir/callback_node"
require_relative "../ir/class_node"
require_relative "../ir/concern_node"
require_relative "../ir/event_publisher_node"
require_relative "../ir/module_node"
require_relative "../ir/route_node"
require_relative "../ir/worker_node"
require_relative "../symbol_identity"

module OllamaAgent
  module Topology
    # Reopened from +staged_graph.rb+ to mix in {SymbolIds}.
    class StagedGraph
      # Computes stable symbol ids per IR node kind for staging and commit.
      module SymbolIds
        private

        # rubocop:disable Metrics/AbcSize -- straight-line kind dispatch; clarity over splitting.
        def symbol_id_for(node)
          return class_module_id(node.fqcn, node.methods, node.origin_extractor_version) if type_node?(node)
          return concern_id(node) if node.is_a?(IR::ConcernNode)
          return worker_id(node) if node.is_a?(IR::WorkerNode)
          return route_id(node) if node.is_a?(IR::RouteNode)
          return callback_id(node) if node.is_a?(IR::CallbackNode)
          return event_id(node) if node.is_a?(IR::EventPublisherNode)

          generic_id(node)
        end
        # rubocop:enable Metrics/AbcSize

        def type_node?(node)
          node.is_a?(IR::ClassNode) || node.is_a?(IR::ModuleNode)
        end

        def class_module_id(fqcn, methods, version)
          SymbolIdentity.compute(
            fqcn: fqcn,
            signature: { fqcn: fqcn, methods: methods.map(&:dup) },
            extractor_version: version
          )
        end

        def concern_id(node)
          SymbolIdentity.compute(
            fqcn: node.fqcn,
            signature: {
              "kind" => "concern",
              "fqcn" => node.fqcn,
              "instance_methods" => node.instance_methods.sort,
              "class_methods" => node.class_methods.sort
            },
            extractor_version: node.origin_extractor_version
          )
        end

        def worker_id(node)
          SymbolIdentity.compute(
            fqcn: node.fqcn,
            signature: { "kind" => "worker", "queue" => node.queue, "perform" => node.perform_signature },
            extractor_version: node.origin_extractor_version
          )
        end

        def route_id(node)
          SymbolIdentity.compute(
            fqcn: node.controller_fqcn,
            signature: {
              "kind" => "route",
              "verb" => node.verb,
              "path" => node.path,
              "action" => node.action_name
            },
            extractor_version: node.origin_extractor_version
          )
        end

        def callback_id(node)
          SymbolIdentity.compute(
            fqcn: node.owner_fqcn,
            signature: { "kind" => "callback", "phase" => node.phase, "method" => node.method_name },
            extractor_version: node.origin_extractor_version
          )
        end

        def event_id(node)
          SymbolIdentity.compute(
            fqcn: node.fqcn,
            signature: {
              "kind" => "event_publisher",
              "event" => node.event_name,
              "schema" => node.payload_schema_ref
            },
            extractor_version: node.origin_extractor_version
          )
        end

        def generic_id(node)
          SymbolIdentity.compute(
            fqcn: node.respond_to?(:fqcn) ? node.fqcn : node.class.name,
            signature: { "kind" => node.kind.to_s },
            extractor_version: node.origin_extractor_version
          )
        end
      end

      include SymbolIds
    end
  end
end

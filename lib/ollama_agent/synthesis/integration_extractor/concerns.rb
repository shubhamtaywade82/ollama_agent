# frozen_string_literal: true

require_relative "../../topology/ir/event_publisher_node"
require_relative "../../topology/ir/route_node"
require_relative "../../topology/ir/worker_node"
require_relative "../../topology/signature_normalizer"
require_relative "../../topology/zeitwerk_inflector"

module OllamaAgent
  module Synthesis
    class IntegrationExtractor
      # Private behavior split for RuboCop and clarity.
      module Concerns
        # Reads instance method names from IR class nodes.
        module MethodReadout
          private

          def method_names(node)
            Array(node.methods).map { |m| (m[:name] || m["name"]).to_s }.uniq
          end

          def method_entry(node, name)
            Array(node.methods).find { |m| (m[:name] || m["name"]).to_s == name }
          end
        end

        # Infers REST {IR::RouteNode} rows from controller class IR.
        module Routes
          private

          def inferred_routes(merged)
            merged.values.flat_map { |node| routes_for_controller(node) }
          end

          def routes_for_controller(node)
            return [] unless node.fqcn.end_with?("Controller")

            actions = present_rest_actions(node)
            return [] if actions.empty?

            resource_segment, ns_segments = controller_path_parts(node.fqcn)
            path_base = (ns_segments + [resource_segment]).join("/")
            actions.flat_map { |action| route_triples_for_action(node, action, path_base) }
          end

          def route_triples_for_action(node, action, path_base)
            spec = rest_route_spec(action)
            return [] unless spec

            verb, suffix = spec
            [build_route(node, verb, "/#{path_base}#{suffix}", action)]
          end

          def rest_route_spec(action)
            {
              "index" => ["GET", ""],
              "show" => ["GET", "/:id"],
              "create" => ["POST", ""],
              "update" => ["PATCH", "/:id"],
              "destroy" => ["DELETE", "/:id"]
            }[action]
          end

          def build_route(node, verb, path, action)
            Topology::IR::RouteNode.build(
              source_path: node.source_path,
              source_line: node.source_line,
              origin_extractor_version: node.origin_extractor_version,
              verb: verb,
              path: path.squeeze("/"),
              controller_fqcn: node.fqcn,
              action_name: action
            )
          end

          def controller_path_parts(fqcn)
            parts = fqcn.split("::")
            controller = parts.pop
            ns = parts.map { |p| Topology::ZeitwerkInflector.underscore(p) }
            resource = Topology::ZeitwerkInflector.underscore(controller.sub(/Controller\z/, ""))
            resource = pluralize_simple(resource)
            [resource, ns]
          end

          def pluralize_simple(word)
            return word if word.end_with?("s")

            "#{word}s"
          end

          def present_rest_actions(node)
            names = method_names(node)
            REST_ACTIONS.select { |a| names.include?(a) }
          end
        end

        # Builds {IR::WorkerNode} rows from Sidekiq includes + +perform+.
        module Workers
          private

          def synthetic_workers(merged)
            merged.values.filter_map { |node| synthetic_worker_for(node) }
          end

          def synthetic_worker_for(node)
            return nil unless node.includes.intersect?(WORKER_MIXINS)

            perform = method_entry(node, "perform")
            return nil unless perform

            Topology::IR::WorkerNode.build(**synthetic_worker_fields(node, perform))
          end

          def synthetic_worker_fields(node, perform)
            {
              source_path: node.source_path,
              source_line: node.source_line,
              origin_extractor_version: node.origin_extractor_version,
              fqcn: node.fqcn,
              queue: "default",
              perform_signature: Topology::SignatureNormalizer.normalize(perform)
            }
          end

          def dedupe_workers(workers)
            by_fqcn = {}
            workers.each { |w| by_fqcn[w.fqcn] = w }
            by_fqcn.values
          end
        end

        # Heuristic {IR::EventPublisherNode} rows from +publish+ / +emit_event+ methods.
        module Publishers
          private

          def heuristic_publishers(merged)
            merged.values.filter_map { |node| heuristic_publisher_for(node) }
          end

          def heuristic_publisher_for(node)
            return nil unless PUBLISHER_METHODS.any? { |m| method_names(node).include?(m) }

            Topology::IR::EventPublisherNode.build(
              source_path: node.source_path,
              source_line: node.source_line,
              origin_extractor_version: node.origin_extractor_version,
              fqcn: node.fqcn,
              event_name: "heuristic",
              payload_schema_ref: nil
            )
          end
        end

        # Detects ActiveRecord models via superclass chain against merged class shards.
        module ArModel
          private

          def ar_model?(node, merged)
            supers = merged.transform_values(&:superclass_fqcn)
            walk = node.fqcn
            seen = {}
            while walk && !AR_ANCESTORS.include?(walk)
              return false if seen[walk]

              seen[walk] = true
              walk = supers[walk]
            end
            AR_ANCESTORS.include?(walk)
          end
        end
      end
    end
  end
end

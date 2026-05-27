# frozen_string_literal: true

require_relative "integration_scan"
require_relative "../topology/class_node_merger"
require_relative "../topology/ir/class_node"
require_relative "../topology/ir/event_publisher_node"
require_relative "../topology/ir/route_node"
require_relative "../topology/ir/worker_node"
require_relative "integration_extractor/concerns"

module OllamaAgent
  module Synthesis
    # Derives integration surface from {Topology::StagedGraph} committed origins only (never staged).
    class IntegrationExtractor
      include Concerns::MethodReadout
      include Concerns::Routes
      include Concerns::Workers
      include Concerns::Publishers
      include Concerns::ArModel

      WORKER_MIXINS = %w[Sidekiq::Worker Sidekiq::Job].freeze
      AR_ANCESTORS = %w[ApplicationRecord ActiveRecord::Base].freeze
      REST_ACTIONS = %w[index show create update destroy].freeze
      PUBLISHER_METHODS = %w[publish emit_event].freeze

      def initialize(staged_graph:)
        @staged_graph = staged_graph
      end

      def extract
        collectors = CommittedCollectors.new
        each_committed { |bundle| absorb_bundle(bundle, collectors) }
        finalize_scan(collectors)
      end

      # Holds parallel arrays while walking committed symbol origins for one extraction pass.
      class CommittedCollectors
        attr_reader :graph_workers, :routes, :event_nodes, :shards

        def initialize
          @graph_workers = []
          @routes = []
          @event_nodes = []
          @shards = Hash.new { |h, k| h[k] = [] }
        end
      end
      private_constant :CommittedCollectors

      private

      def each_committed(&)
        @staged_graph.committed_symbols_with_origins(&)
      end

      def absorb_bundle(bundle, collectors)
        node = bundle[:ir_node_aggregate]
        bucket = collector_bucket_for(node, collectors)
        bucket << node if bucket
      end

      def collector_bucket_for(node, collectors)
        case node
        when Topology::IR::WorkerNode then collectors.graph_workers
        when Topology::IR::RouteNode then collectors.routes
        when Topology::IR::EventPublisherNode then collectors.event_nodes
        when Topology::IR::ClassNode then collectors.shards[node.fqcn]
        end
      end

      def finalize_scan(collectors)
        merged = collectors.shards.transform_values { |list| merge_class_shards(list) }
        build_integration_scan(collectors, merged)
      end

      def build_integration_scan(collectors, merged)
        workers = dedupe_workers(collectors.graph_workers + synthetic_workers(merged)).sort_by(&:fqcn)
        routes = stable_routes(collectors.routes + inferred_routes(merged))
        publishers = stable_publishers(collectors.event_nodes + heuristic_publishers(merged))
        IntegrationScan.new(
          routes: routes,
          workers: workers,
          event_publishers: publishers,
          ar_models: ar_models_for(merged)
        )
      end

      def ar_models_for(merged)
        merged.values.select { |c| ar_model?(c, merged) }.sort_by(&:fqcn)
      end

      def merge_class_shards(list)
        return list.first if list.one?

        Topology::ClassNodeMerger.merge(list)
      end

      def stable_routes(routes)
        routes.uniq.sort_by { |r| [r.controller_fqcn, r.verb, r.path, r.action_name] }
      end

      def stable_publishers(list)
        list.uniq.sort_by { |e| [e.fqcn, e.event_name] }
      end
    end
  end
end

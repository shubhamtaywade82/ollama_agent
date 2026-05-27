# frozen_string_literal: true

module OllamaAgent
  module Topology
    class Linker
      # Post-link consistency: superclass reachability and include DAG cycles.
      class Validate
        STDLIB_SUPER = %w[Object BasicObject].freeze

        def call(aggregated:, linked:)
          errors = orphan_superclasses(aggregated, linked)
          errors.concat(include_cycles(aggregated))
          { valid: errors.empty?, errors: errors }
        end

        private

        def orphan_superclasses(aggregated, linked)
          inheritance = linked.is_a?(Hash) ? linked[:inheritance] : {}
          aggregated.flat_map do |fqcn, meta|
            orphan_super_for(fqcn, meta, aggregated, inheritance)
          end
        end

        def orphan_super_for(fqcn, meta, aggregated, inheritance)
          sc = inheritance&.fetch(fqcn, nil) || meta[:superclass_fqcn]
          return [] unless orphan_super_candidate?(sc, aggregated)

          files = Array(meta[:origins]).map(&:source_path).uniq
          [{ type: :orphan_superclass, message: "#{fqcn} superclass #{sc} not indexed", file_paths: files }]
        end

        def orphan_super_candidate?(superclass, aggregated)
          return false if superclass.nil? || superclass.empty?
          return false if STDLIB_SUPER.include?(superclass)
          return false if aggregated.key?(superclass)

          true
        end

        def include_cycles(aggregated)
          graph = build_include_graph(aggregated)
          cycle = dfs_find_cycle(graph)
          return [] unless cycle

          sep = " -> "
          [{ type: :include_cycle, message: "include cycle: #{cycle.join(sep)}", file_paths: [] }]
        end

        def build_include_graph(aggregated)
          graph = {}
          aggregated.each_key { |fq| graph[fq] = [] }
          aggregated.each do |owner, meta|
            Array(meta[:includes]).each do |inc|
              graph[owner] << inc if graph.key?(inc)
            end
          end
          graph
        end

        def dfs_find_cycle(graph)
          state = {}
          stack = []
          graph.each_key do |start|
            found = visit_cycle(start, graph, state, stack)
            return found if found
          end
          nil
        end

        def visit_cycle(node, graph, state, stack)
          return handle_visiting(node, stack) if state[node] == :visiting
          return nil if state[node] == :done

          descend(node, graph, state, stack)
        end

        def handle_visiting(node, stack)
          idx = stack.index(node)
          stack[idx..] if idx
        end

        def descend(node, graph, state, stack)
          state[node] = :visiting
          stack << node
          graph[node].each do |nxt|
            cyc = visit_cycle(nxt, graph, state, stack)
            return cyc if cyc
          end
          stack.pop
          state[node] = :done
          nil
        end
      end
    end
  end
end

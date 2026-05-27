# frozen_string_literal: true

require_relative "../../ir/node"
require_relative "../../ir/class_node"
require_relative "../../ir/concern_node"
require_relative "../../ir/module_node"
require_relative "../../ir/worker_node"
require_relative "../../signature_normalizer"

module OllamaAgent
  module Topology
    module Extractors
      # Reopened in this file — see +ruby_semantic_extractor.rb+ for the superclass.
      class RubySemanticExtractor
        # Emits frozen IR nodes while visiting; relies on extractor ivars (+@nodes+, +@file_path+).
        module IrNodesEmitter
          def emit_concern(ctx)
            @nodes << IR::ConcernNode.build(
              source_path: @file_path,
              source_line: ctx[:line],
              origin_extractor_version: EXTRACTOR_VERSION,
              fqcn: ctx[:fqcn],
              included_modules: [],
              class_methods: ctx[:class_method_names].uniq.sort,
              instance_methods: ctx[:instance_method_names].uniq.sort
            )
          end

          def emit_class(ctx)
            @nodes << IR::ClassNode.build(source_path: @file_path, source_line: ctx[:line],
                                          origin_extractor_version: EXTRACTOR_VERSION, fqcn: ctx[:fqcn],
                                          superclass_fqcn: ctx[:superclass_fqcn], module_chain: ctx[:module_chain],
                                          methods: ctx[:methods], includes: ctx[:includes].uniq,
                                          extends: ctx[:extends].uniq)
          end

          def emit_module(ctx)
            @nodes << IR::ModuleNode.build(
              source_path: @file_path,
              source_line: ctx[:line],
              origin_extractor_version: EXTRACTOR_VERSION,
              fqcn: ctx[:fqcn],
              module_chain: ctx[:module_chain],
              methods: ctx[:methods]
            )
          end

          def emit_worker_if_needed(ctx)
            return unless ctx[:sidekiq_worker]

            perform = ctx[:methods].find { |m| m[:name].to_s == "perform" }
            return unless perform

            sig = SignatureNormalizer.normalize(perform)
            @nodes << IR::WorkerNode.build(source_path: @file_path, source_line: ctx[:line],
                                           origin_extractor_version: EXTRACTOR_VERSION, fqcn: ctx[:fqcn],
                                           queue: "default", perform_signature: sig)
          end
        end

        include IrNodesEmitter
      end
    end
  end
end

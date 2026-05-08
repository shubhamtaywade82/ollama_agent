# frozen_string_literal: true

module OllamaAgent
  module Topology
    module Extractors
      class RubySemanticExtractor
        # Mutable per-scope accumulator while visiting a class or module body.
        module SemanticContext
          module_function

          def build(kind:, fqcn:, module_chain:, superclass_fqcn:, line:)
            scope_identity(kind, fqcn, module_chain, superclass_fqcn, line).merge(mutable_slots)
          end

          def scope_identity(kind, fqcn, module_chain, superclass_fqcn, line)
            {
              kind: kind,
              fqcn: fqcn,
              module_chain: module_chain,
              superclass_fqcn: superclass_fqcn,
              line: line
            }
          end

          def mutable_slots
            {
              includes: [],
              extends: [],
              methods: [],
              instance_method_names: [],
              class_method_names: [],
              in_class_methods_block: 0,
              sidekiq_worker: false
            }
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require "prism"

module OllamaAgent
  module Topology
    module Extractors
      class RubySemanticExtractor
        # Builds a flat parameter descriptor list from a Prism parameters node.
        module ParameterList
          module_function

          def build(params_node)
            return [] unless params_node.is_a?(Prism::ParametersNode)

            positional(params_node) +
              optional_positionals(params_node) +
              rest_part(params_node) +
              keyword_parts(params_node) +
              kwrest_part(params_node) +
              block_part(params_node)
          end

          def positional(params_node)
            params_node.requireds.map { |p| { kind: "positional", name: p.name.to_s } }
          end

          def optional_positionals(params_node)
            params_node.optionals.map { |p| { kind: "optional_positional", name: p.name.to_s } }
          end

          def rest_part(params_node)
            rest = params_node.rest
            return [] unless rest

            [{ kind: "rest", name: (rest.name || :args).to_s }]
          end

          def keyword_parts(params_node)
            params_node.keywords.flat_map { |p| keyword_entry(p) }
          end

          def keyword_entry(param)
            case param
            when Prism::RequiredKeywordParameterNode
              [{ kind: "keyword_required", name: param.name.to_s }]
            when Prism::OptionalKeywordParameterNode
              [{ kind: "keyword_optional", name: param.name.to_s }]
            else
              []
            end
          end

          def kwrest_part(params_node)
            kwrest = params_node.keyword_rest
            return [] unless kwrest

            [{ kind: "kwrest", name: (kwrest.name || :kwrest).to_s }]
          end

          def block_part(params_node)
            blk = params_node.block
            return [] unless blk

            [{ kind: "block", name: (blk.name || :block).to_s }]
          end
        end
      end
    end
  end
end

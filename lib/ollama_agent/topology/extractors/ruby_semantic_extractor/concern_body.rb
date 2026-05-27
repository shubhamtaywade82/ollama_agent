# frozen_string_literal: true

require "prism"

require_relative "../../../ruby_index/naming"

module OllamaAgent
  module Topology
    module Extractors
      class RubySemanticExtractor
        # Detects ActiveSupport::Concern usage inside a class/module body.
        module ConcernBody
          module_function

          def concern?(body)
            statement_items(body).any? { |stmt| concern_call?(stmt) }
          end

          def statement_items(body)
            return [] unless body.is_a?(Prism::StatementsNode)

            Array(body.body)
          end

          def concern_call?(stmt)
            stmt.is_a?(Prism::CallNode) && concern_invocation?(stmt)
          end

          def concern_invocation?(call)
            return false unless %i[extend include].include?(call.name)
            return false if call.receiver

            arg = call.arguments&.arguments&.first
            concern_fqcn?(arg)
          end

          def concern_fqcn?(arg)
            fq = OllamaAgent::RubyIndex::Naming.full_constant_path(arg).to_s
            fq == "ActiveSupport::Concern" || fq.end_with?("::ActiveSupport::Concern")
          end
        end
      end
    end
  end
end

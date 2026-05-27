# frozen_string_literal: true

require_relative "../topology/zeitwerk_inflector"
require_relative "integration_extractor"

module OllamaAgent
  module Synthesis
    # Builds deterministic +routes.rb+ fragments from {IntegrationExtractor} output.
    class RouteSynthesizer
      REST_ORDER = IntegrationExtractor::REST_ACTIONS

      def initialize(integration_extractor:)
        @integration_extractor = integration_extractor
      end

      def synthesize
        scan = @integration_extractor.extract
        grouped = scan.routes.group_by(&:controller_fqcn)
        blocks = grouped.keys.sort.map { |fqcn| emit_controller_block(fqcn, grouped[fqcn]) }
        "#{blocks.join("\n\n")}\n"
      end

      private

      def emit_controller_block(fqcn, routes)
        actions = routes.map(&:action_name).uniq.sort_by { |a| REST_ORDER.index(a) || 99 }
        parts = fqcn.split("::")
        controller = parts.pop
        resource = pluralize_simple(Topology::ZeitwerkInflector.underscore(controller.sub(/Controller\z/, "")))
        only = actions.map { |a| ":#{a}" }.join(", ")
        inner = "resources :#{resource}, only: [#{only}]"
        return inner if parts.empty?

        wrap_namespaces(parts, inner)
      end

      def wrap_namespaces(namespace_parts, inner)
        opens = namespace_opener_lines(namespace_parts)
        depth = namespace_parts.size
        body = "#{" " * (2 * depth)}#{inner}"
        closes = depth.downto(1).map { |d| "#{" " * (2 * (d - 1))}end" }
        (opens + [body] + closes).join("\n")
      end

      def namespace_opener_lines(namespace_parts)
        namespace_parts.each_with_index.map do |ns, idx|
          "#{" " * (2 * idx)}namespace :#{Topology::ZeitwerkInflector.underscore(ns)} do"
        end
      end

      def pluralize_simple(word)
        return word if word.end_with?("s")

        "#{word}s"
      end
    end
  end
end

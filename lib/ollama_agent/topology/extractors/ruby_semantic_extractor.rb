# frozen_string_literal: true

require "prism"

module OllamaAgent
  module Topology
    module Extractors
      # Single-file Prism walk producing typed IR nodes (E11a; linker in E11b).
      class RubySemanticExtractor < Prism::Visitor
        EXTRACTOR_VERSION = "1.0.0"

        # Wraps Prism parse failures so callers can log or surface diagnostics.
        class ParseError < StandardError
          attr_reader :file_path, :messages

          def initialize(file_path, messages)
            super("parse failed: #{file_path}")
            @file_path = file_path
            @messages = Array(messages)
          end
        end

        attr_accessor :on_parse_error

        def initialize
          super
          @on_parse_error = nil
          @file_path = nil
          @nodes = []
          @pending = []
          @namespace_stack = []
          @context_stack = []
        end

        def extract(file_path:)
          reset!(file_path)
          result = Prism.parse(File.read(file_path), filepath: file_path)
          if result.failure?
            @on_parse_error&.call(ParseError.new(file_path, result.errors.map(&:message)))
            return []
          end

          result.value.accept(self)
          @nodes.concat(@pending)
          @nodes
        end

        private

        def reset!(file_path)
          @file_path = file_path.to_s
          @nodes = []
          @pending = []
          @namespace_stack = []
          @context_stack = []
        end
      end
    end
  end
end

require_relative "ruby_semantic_extractor/parameter_list"
require_relative "ruby_semantic_extractor/semantic_context"
require_relative "ruby_semantic_extractor/concern_body"
require_relative "ruby_semantic_extractor/ir_nodes_emitter"
require_relative "ruby_semantic_extractor/mixin_dispatch"
require_relative "ruby_semantic_extractor/navigation"

# frozen_string_literal: true

module OllamaAgent
  module Topology
    class Linker
      # Runs {RubySemanticExtractor} across discovered files; captures parse diagnostics.
      class Extract
        def initialize(extractor:)
          @extractor = extractor
        end

        def call(files:)
          by_file = {}
          errors = {}
          Array(files).each { |path| extract_one(path, by_file, errors) }
          { ir_by_file: by_file, parse_errors: errors }
        end

        private

        def extract_one(path, by_file, errors)
          capture = nil
          @extractor.on_parse_error = ->(err) { capture = err }
          nodes = @extractor.extract(file_path: path)
          abs = File.expand_path(path)
          if capture
            errors[abs] = capture.message
          else
            by_file[abs] = nodes
          end
        end
      end
    end
  end
end

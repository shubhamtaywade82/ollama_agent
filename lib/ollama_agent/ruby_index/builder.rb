# frozen_string_literal: true

require "find"
require "pathname"

require "prism"

require_relative "extractor_visitor"

module OllamaAgent
  module RubyIndex
    # Scans `.rb` files under root, parses with Prism, and merges index entries.
    module Builder
      module_function

      DEFAULT_MAX_FILES = 5000
      DEFAULT_MAX_FILE_BYTES = 512_000

      def build(root:, max_files: nil, max_file_bytes: nil)
        Run.new(
          root: root,
          max_files: max_files,
          max_file_bytes: max_file_bytes
        ).call
      end

      def env_int(name)
        v = ENV.fetch(name, nil)
        return nil if v.nil? || v.empty?

        Integer(v)
      rescue ArgumentError
        nil
      end

      # rubocop:disable Metrics/MethodLength -- Find.find callback
      def each_rb_relative_path(root_path, max_files)
        count = 0
        Find.find(root_path.to_s) do |path|
          if File.directory?(path) && File.basename(path) == ".git"
            Find.prune
            next
          end

          next unless File.file?(path)
          next unless path.end_with?(".rb")

          rel = Pathname(path).relative_path_from(root_path).to_s
          yield rel
          count += 1
          break if count >= max_files
        end
      end
      # rubocop:enable Metrics/MethodLength

      # Orchestrates file discovery and Prism parsing.
      class Run
        def initialize(root:, max_files:, max_file_bytes:)
          @root_path = Pathname(root).expand_path
          @max_files = normalized_max_files(max_files)
          @max_file_bytes = normalized_max_bytes(max_file_bytes)
          @constants = []
          @methods = []
          @errors = []
          @files_indexed = 0
        end

        def call
          Builder.each_rb_relative_path(@root_path, @max_files) { |rel| ingest(rel) }
          Index.new(
            root: @root_path.to_s,
            constants: @constants.sort_by { |r| [r[:path], r[:start_line], r[:name]] },
            methods: @methods.sort_by { |r| [r[:path], r[:start_line], r[:name]] },
            errors: @errors,
            files_indexed: @files_indexed
          )
        end

        private

        def normalized_max_files(value)
          n = (value || Builder.env_int("OLLAMA_AGENT_RUBY_INDEX_MAX_FILES") || DEFAULT_MAX_FILES).to_i
          [n, 1].max
        end

        def normalized_max_bytes(value)
          n = (value || Builder.env_int("OLLAMA_AGENT_RUBY_INDEX_MAX_FILE_BYTES") || DEFAULT_MAX_FILE_BYTES).to_i
          [n, 1024].max
        end

        def ingest(rel)
          abs = @root_path.join(rel).to_s
          return unless File.file?(abs)
          return if File.size(abs) > @max_file_bytes

          append_parse_result(rel, abs, File.read(abs))
        end

        def append_parse_result(rel, abs, source)
          result = Prism.parse(source, filepath: abs)
          unless result.success?
            @errors << "#{rel}: #{result.errors.map(&:message).join(", ")}"
            return
          end

          visitor = ExtractorVisitor.new(rel.to_s)
          result.value.accept(visitor)
          @constants.concat(visitor.constants)
          @methods.concat(visitor.methods)
          @files_indexed += 1
        end
      end
    end
  end
end

# frozen_string_literal: true

module OllamaAgent
  module Topology
    # Path ↔ constant guessing aligned with common Zeitwerk / Rails autoload layout.
    module ZeitwerkInflector
      module_function

      DEFAULT_ROOTS = %w[app/models app/controllers lib].freeze

      def camelize(snake_path:, acronyms: {})
        snake_path.to_s.split("/").map { |segment| camelize_segment(segment, acronyms) }.join("::")
      end

      def file_to_constant(file_path:, root_paths: DEFAULT_ROOTS, acronyms: {})
        abs = File.expand_path(file_path.to_s)
        root = matching_root(abs, root_paths.map { |r| File.expand_path(r.to_s) })
        return fallback_constant(abs, acronyms) unless root

        rel = abs.delete_prefix("#{root}#{File::SEPARATOR}")
        rel = rel.sub(/\.rb\z/, "")
        camelize(snake_path: rel.tr(File::SEPARATOR, "/"), acronyms: acronyms)
      end

      def constant_to_file_pattern(fqcn:, root_paths: DEFAULT_ROOTS)
        parts = fqcn.to_s.split("::")
        snake_segments = parts.map { |part| underscore(part) }
        root_paths.map do |root|
          joined = File.join(File.expand_path(root.to_s), *snake_segments)
          "#{joined}.rb"
        end
      end

      def matching_root(abs_path, expanded_roots)
        expanded_roots
          .select { |r| abs_path.start_with?("#{r}#{File::SEPARATOR}") || abs_path == r }
          .max_by(&:length)
      end

      def fallback_constant(abs_path, acronyms)
        base = File.basename(abs_path, ".rb")
        camelize(snake_path: base, acronyms: acronyms)
      end

      def camelize_segment(segment, acronyms)
        return "" if segment.empty?

        pieces = segment.split("_")
        pieces.map { |piece| camelize_piece(piece, acronyms) }.join
      end

      def camelize_piece(piece, acronyms)
        key = piece.downcase
        return acronyms[key] if acronyms[key]

        piece.capitalize
      end

      def underscore(const_part)
        return "" if const_part.to_s.empty?

        const_part
          .gsub("::", "/")
          .gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .tr("-", "_")
          .downcase
      end
    end
  end
end

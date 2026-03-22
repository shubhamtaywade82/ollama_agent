# frozen_string_literal: true

module OllamaAgent
  module RubyIndex
    # Immutable snapshot of class/module and method definitions for a tree.
    class Index
      attr_reader :root, :constants, :methods, :errors, :files_indexed

      def initialize(root:, constants:, methods:, errors:, files_indexed:)
        @root = root
        @constants = constants.freeze
        @methods = methods.freeze
        @errors = errors.freeze
        @files_indexed = files_indexed
      end

      def search_class(pattern)
        match_records(@constants.select { |r| r[:kind] == :class }, pattern)
      end

      def search_module(pattern)
        match_records(@constants.select { |r| r[:kind] == :module }, pattern)
      end

      def search_class_or_module(pattern)
        match_records(@constants, pattern)
      end

      def search_method(pattern)
        match_records(@methods, pattern, field: :name)
      end

      def summary_line
        "ruby_index: #{@files_indexed} files, #{@constants.size} classes/modules, #{@methods.size} methods" \
          "#{", #{@errors.size} parse warning(s)" unless errors.empty?}"
      end

      private

      def match_records(records, pattern, field: :name)
        needle = pattern.to_s
        return records.dup if needle.empty?

        records.select do |r|
          name = r[field].to_s
          name.include?(needle)
        end
      end
    end
  end
end

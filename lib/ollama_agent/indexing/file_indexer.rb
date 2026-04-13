# frozen_string_literal: true

require_relative "repo_scanner"

module OllamaAgent
  module Indexing
    # Builds a searchable in-memory index of files in the repository.
    # Extracts: file paths, function/class names (Ruby), and word tokens.
    # Used by ContextPacker to score files for relevance to a query.
    class FileIndexer
      IndexEntry = Data.define(:relative_path, :language, :symbols, :tokens, :size)

      MAX_FILE_BYTES = 512_000 # 500 KB — skip larger files for indexing

      def initialize(root:, scanner: nil)
        @root    = File.expand_path(root)
        @scanner = scanner || RepoScanner.new(root: @root)
        @index   = nil
      end

      # Build or return the cached index.
      # @param force [Boolean] rebuild even if cached
      # @return [Array<IndexEntry>]
      def build(force: false)
        return @index if @index && !force

        @index = @scanner.scan.filter_map { |entry| index_file(entry) }
      end

      # Search index for entries relevant to a query string.
      # Returns entries sorted by score (highest first).
      # @param query      [String]
      # @param top_n      [Integer]
      # @param languages  [Array<Symbol>, nil]
      def search(query, top_n: 20, languages: nil)
        idx = build

        keywords = tokenize(query).uniq
        return idx.first(top_n) if keywords.empty?

        scored = idx.map do |entry|
          next if languages && !languages.include?(entry.language)

          score = score_entry(entry, keywords)
          [entry, score]
        end.compact

        scored.sort_by { |_, s| -s }
              .first(top_n)
              .map(&:first)
      end

      # Invalidate and rebuild the index.
      def refresh!
        build(force: true)
      end

      def indexed_count
        build.size
      end

      private

      def index_file(file_entry)
        return nil if file_entry.size > MAX_FILE_BYTES

        content = File.read(file_entry.path, encoding: "utf-8", invalid: :replace)
        symbols = extract_symbols(content, file_entry.language)
        tokens  = tokenize("#{content} #{file_entry.relative_path}")

        IndexEntry.new(
          relative_path: file_entry.relative_path,
          language: file_entry.language,
          symbols: symbols,
          tokens: tokens,
          size: file_entry.size
        )
      rescue StandardError
        nil
      end

      def extract_symbols(content, language)
        case language
        when :ruby then extract_ruby_symbols(content)
        when :javascript,
             :typescript then extract_js_symbols(content)
        when :python     then extract_python_symbols(content)
        else []
        end
      end

      def extract_ruby_symbols(content)
        symbols = []
        content.scan(/^\s*(?:def|class|module|attr_\w+)\s+(\w+)/) { |m| symbols << m[0] }
        symbols
      end

      def extract_js_symbols(content)
        symbols = []
        content.scan(/(?:function\s+|class\s+|const\s+|let\s+|var\s+)(\w+)/) { |m| symbols << m[0] }
        symbols
      end

      def extract_python_symbols(content)
        symbols = []
        content.scan(/^(?:def|class)\s+(\w+)/) { |m| symbols << m[0] }
        symbols
      end

      def tokenize(text)
        text.downcase
            .scan(/[a-z][a-z0-9_]{2,}/)
            .uniq
      end

      def score_entry(entry, keywords)
        path_tokens = tokenize(entry.relative_path)
        sym_tokens  = entry.symbols.map(&:downcase)

        keywords.sum do |kw|
          path_match   = path_tokens.any? { |t| t.include?(kw) } ? 3 : 0
          symbol_match = sym_tokens.any?  { |s| s.include?(kw) } ? 2 : 0
          token_match  = entry.tokens.any? { |t| t.include?(kw) } ? 1 : 0
          path_match + symbol_match + token_match
        end
      end
    end
  end
end

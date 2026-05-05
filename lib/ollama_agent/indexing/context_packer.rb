# frozen_string_literal: true

require_relative "repo_scanner"
require_relative "file_indexer"

module OllamaAgent
  module Indexing
    # Builds a compact, query-relevant context block from the repository.
    # Used to inject surgical context into the system prompt instead of
    # reading entire files blindly.
    #
    # @example
    #   packer = OllamaAgent::Indexing::ContextPacker.new(root: Dir.pwd)
    #   context = packer.pack(query: "fix the authentication module")
    #   # => "# lib/auth/session.rb\n```ruby\n...\n```\n\n# lib/auth/token.rb\n..."
    class ContextPacker
      DEFAULT_MAX_FILES = 15
      DEFAULT_MAX_FILE_BYTES = 8_192     # 8 KB per file in context
      DEFAULT_MAX_TOTAL_BYTES = 65_536   # 64 KB total context

      def initialize(root:, max_files: DEFAULT_MAX_FILES,
                     max_file_bytes: DEFAULT_MAX_FILE_BYTES,
                     max_total_bytes: DEFAULT_MAX_TOTAL_BYTES,
                     indexer: nil)
        @root            = File.expand_path(root)
        @max_files       = max_files
        @max_file_bytes  = max_file_bytes
        @max_total_bytes = max_total_bytes
        @indexer         = indexer || FileIndexer.new(root: @root)
      end

      # Pack the most relevant files for a query.
      # @param query    [String]       natural-language query for scoring
      # @param files    [Array, nil]   explicit relative paths (bypasses scoring)
      # @param languages [Array, nil]  filter to specific languages
      # @return [String]  formatted context block (Markdown fenced code)
      def pack(query: nil, files: nil, languages: nil)
        candidates = if files
                       files.map { |f| File.expand_path(f, @root) }
                     elsif query
                       relevant_paths(query, languages: languages)
                     else
                       recently_modified_paths
                     end

        build_context(candidates)
      end

      # Return a repo-summary block (structure, file counts, recent changes).
      def repo_summary
        scanner = RepoScanner.new(root: @root)
        stats   = scanner.stats

        lines = ["## Repository Summary", "Root: #{@root}", ""]
        lines << "### File counts by language"
        stats[:languages]
          .sort_by { |_, v| -v[:files] }
          .first(10)
          .each { |lang, info| lines << "- #{lang}: #{info[:files]} files (#{human_bytes(info[:bytes])})" }

        lines << ""
        lines << "### Recently modified (top 10)"
        scanner.recently_modified(n: 10).each do |f|
          lines << "- #{f.relative_path} (#{human_bytes(f.size)})"
        end

        lines.join("\n")
      end

      private

      def relevant_paths(query, languages: nil)
        entries = @indexer.search(query, top_n: @max_files, languages: languages)
        entries.map { |e| File.join(@root, e.relative_path) }
      end

      def recently_modified_paths
        scanner = RepoScanner.new(root: @root)
        scanner.recently_modified(n: @max_files).map(&:path)
      end

      def build_context(paths)
        parts = []
        total_bytes = 0

        paths.each do |abs_path|
          break if total_bytes >= @max_total_bytes
          break if parts.size >= @max_files

          next unless File.file?(abs_path)

          rel     = abs_path.sub("#{@root}/", "")
          content = read_truncated(abs_path)
          lang    = detect_fence_lang(abs_path)

          block       = "### #{rel}\n```#{lang}\n#{content}\n```"
          block_bytes = block.bytesize

          break if total_bytes + block_bytes > @max_total_bytes

          parts       << block
          total_bytes += block_bytes
        end

        parts.empty? ? "" : parts.join("\n\n")
      end

      def read_truncated(path)
        raw = File.read(path, encoding: "utf-8", invalid: :replace)
        if raw.bytesize > @max_file_bytes
          raw.byteslice(0, @max_file_bytes) + "\n# ... [truncated — #{human_bytes(raw.bytesize)} total]"
        else
          raw
        end
      rescue StandardError
        "[unreadable]"
      end

      def detect_fence_lang(path)
        ext_map = {
          ".rb" => "ruby", ".js" => "javascript", ".ts" => "typescript",
          ".py" => "python", ".go" => "go", ".rs" => "rust", ".java" => "java",
          ".sh" => "bash", ".yml" => "yaml", ".yaml" => "yaml",
          ".json" => "json", ".md" => "markdown", ".html" => "html",
          ".css" => "css", ".sql" => "sql", ".ex" => "elixir", ".exs" => "elixir"
        }
        ext_map[File.extname(path).downcase] || ""
      end

      def human_bytes(n)
        return "#{n} B" if n < 1024

        n /= 1024.0
        return "#{n.round(1)} KB" if n < 1024

        "#{(n / 1024.0).round(1)} MB"
      end
    end
  end
end

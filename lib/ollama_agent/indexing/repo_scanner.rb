# frozen_string_literal: true

require "find"

module OllamaAgent
  module Indexing
    # Scans a repository and returns a file inventory with language tags.
    # Language detection is extension-based (no external gems required).
    # Used by ContextPacker to select relevant files for the agent context.
    class RepoScanner
      LANGUAGE_EXTENSIONS = {
        ruby:        %w[.rb .rake .gemspec],
        javascript:  %w[.js .jsx .mjs .cjs],
        typescript:  %w[.ts .tsx],
        python:      %w[.py .pyw],
        go:          %w[.go],
        rust:        %w[.rs],
        java:        %w[.java],
        kotlin:      %w[.kt .kts],
        swift:       %w[.swift],
        cpp:         %w[.cpp .cc .cxx .hpp .hh .h],
        c:           %w[.c .h],
        csharp:      %w[.cs],
        php:         %w[.php],
        elixir:      %w[.ex .exs],
        erlang:      %w[.erl .hrl],
        haskell:     %w[.hs .lhs],
        scala:       %w[.scala],
        clojure:     %w[.clj .cljs .cljc],
        shell:       %w[.sh .bash .zsh .fish],
        yaml:        %w[.yml .yaml],
        json:        %w[.json .jsonc],
        toml:        %w[.toml],
        markdown:    %w[.md .mdx .markdown],
        html:        %w[.html .htm .xhtml],
        css:         %w[.css .scss .sass .less],
        sql:         %w[.sql],
        dockerfile:  %w[Dockerfile],
        terraform:   %w[.tf .tfvars],
        proto:       %w[.proto]
      }.freeze

      IGNORED_DIRS = %w[
        .git .svn .hg .bzr
        node_modules vendor .bundle
        tmp log coverage .nyc_output dist build out target
        __pycache__ .pytest_cache .mypy_cache .tox venv env .venv
        .ollama_agent .idea .vscode .cursor
      ].freeze

      IGNORED_FILES = %w[
        Gemfile.lock yarn.lock package-lock.json pnpm-lock.yaml
        .DS_Store Thumbs.db *.min.js *.min.css
      ].freeze

      FileEntry = Data.define(:path, :relative_path, :language, :size, :modified_at)

      def initialize(root:, exclude_dirs: nil, max_file_size: 1_048_576)
        @root            = File.expand_path(root)
        @exclude_dirs    = (exclude_dirs || []) + IGNORED_DIRS
        @max_file_size   = max_file_size
        @ext_map         = build_ext_map
      end

      # Scan the repository and return FileEntry objects.
      # @param languages [Array<Symbol>, nil]  filter to specific languages
      # @return [Array<FileEntry>]
      def scan(languages: nil)
        results = []

        Find.find(@root) do |path|
          basename = File.basename(path)

          if File.directory?(path)
            Find.prune if prune_dir?(path, basename)
            next
          end

          next unless File.file?(path)
          next if ignored_file?(basename)

          size = File.size(path)
          next if size > @max_file_size

          lang = detect_language(path)
          next if languages && !languages.map(&:to_sym).include?(lang)

          rel = path.sub("#{@root}/", "")
          results << FileEntry.new(
            path:          path,
            relative_path: rel,
            language:      lang,
            size:          size,
            modified_at:   File.mtime(path)
          )
        rescue StandardError
          next
        end

        results.sort_by(&:relative_path)
      end

      # Summary statistics about the repository.
      def stats
        files = scan
        by_lang = files.group_by(&:language)

        {
          total_files:  files.size,
          total_bytes:  files.sum(&:size),
          root:         @root,
          languages:    by_lang.transform_values { |fs| { files: fs.size, bytes: fs.sum(&:size) } }
        }
      end

      # Files most recently modified.
      def recently_modified(n: 20)
        scan.max_by(n, &:modified_at)
      end

      private

      def build_ext_map
        map = {}
        LANGUAGE_EXTENSIONS.each do |lang, exts|
          exts.each { |ext| map[ext.downcase] = lang }
        end
        map
      end

      def detect_language(path)
        base = File.basename(path)
        return :dockerfile if base == "Dockerfile"
        return :ruby if base.match?(/\A(Rakefile|Gemfile|Guardfile|Capfile|Brewfile)\z/)

        ext = File.extname(path).downcase
        @ext_map[ext] || :other
      end

      def prune_dir?(path, basename)
        return true if basename.start_with?(".")
        return true if @exclude_dirs.include?(basename)

        @exclude_dirs.any? { |d| path.include?("/#{d}/") || path.end_with?("/#{d}") }
      end

      def ignored_file?(basename)
        IGNORED_FILES.any? do |pattern|
          if pattern.include?("*")
            File.fnmatch(pattern, basename)
          else
            basename == pattern
          end
        end
      end
    end
  end
end

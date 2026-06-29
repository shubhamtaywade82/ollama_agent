# frozen_string_literal: true

require_relative "base"
require_relative "enhanced_registry"

module OllamaAgent
  module Tools
    class SearchSymbols < Base
      tool_name        "search_symbols"
      tool_description "Find Ruby class, module, method, or constant definitions by name pattern (Prism AST)."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      pattern: { type: "string", description: "Name pattern to search (substring match)" },
                      kind: {
                        type: "string",
                        enum: %w[class module method constant],
                        description: "Kind of symbol to search"
                      }
                    },
                    required: ["pattern"]
                  })

      def call(args, context: {})
        root    = context[:root] || Dir.pwd
        pattern = args["pattern"].to_s
        kind    = args["kind"] || "class"

        idx = RubyIndex.build(root: root)
        rows = case kind
               when "class"    then idx.search_class(pattern)
               when "module"   then idx.search_module(pattern)
               when "constant" then idx.search_class_or_module(pattern)
               when "method"   then idx.search_method(pattern)
               else return "Error: unknown kind #{kind}"
               end

        return "No symbols found matching #{pattern.inspect}" if rows.empty?

        rows.map do |r|
          f = r[:file].delete_prefix("#{root}/")
          "#{r[:kind]} #{r[:name]} at #{f}:#{r[:line]}"
        end.join("\n")
      end
    end

    class FindReferences < Base
      tool_name        "find_references"
      tool_description "Find all usages of a symbol across the codebase. Excludes definition lines."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Symbol name to find references for" },
                      directory: { type: "string", description: "Search root (default: project root)" }
                    },
                    required: ["symbol"]
                  })

      def call(args, context: {})
        root  = context[:root] || Dir.pwd
        sym   = args["symbol"].to_s
        dir   = args["directory"] || "."
        return "Error: symbol is required" if sym.empty?

        rg = SearchBackend.rg_executable
        out = if rg
                `#{rg} -n -- #{Shellwords.shellescape(sym)} #{Shellwords.shellescape(File.expand_path(dir, root))}`.lines
              else
                `grep -rn -- #{Shellwords.shellescape(sym)} #{Shellwords.shellescape(File.expand_path(dir, root))}`.lines
              end

        refs = out.grep_v(/^\d+:\s*(def |class |module |\s*#\s*)/)
                  .map(&:strip)
        return "No references found for #{sym.inspect}" if refs.empty?

        refs.first(50).join("\n") + (refs.size > 50 ? "\n...[#{refs.size - 50} more]" : "")
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end

    class GrepAst < Base
      tool_name        "grep_ast"
      tool_description "Query the AST of Ruby files — find all method calls to X, all rescue blocks, etc."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      query: { type: "string", description: "AST node type to find (e.g. 'rescue', 'send', 'class')" },
                      file: { type: "string", description: "File path relative to project root" }
                    },
                    required: %w[query file]
                  })

      def call(args, context: {})
        root  = context[:root] || Dir.pwd
        query = args["query"].to_s
        file  = File.expand_path(args["file"], root)
        return "Error: file not found" unless File.exist?(file)

        src = File.read(file)
        require "prism"
        tree = Prism.parse(src)

        results = find_nodes(tree.value, query)
        return "No AST nodes matching #{query.inspect} found" if results.empty?

        results.map do |loc|
          lines = src.lines[(loc.start_line - 1)..(loc.end_line - 1)]
          "#{args["file"]}:#{loc.start_line}-#{loc.end_line}\n#{lines.join.chomp}"
        end.join("\n---\n")
      rescue LoadError
        "Error: prism gem not available"
      rescue StandardError => e
        "Error: #{e.message}"
      end

      private

      def find_nodes(node, query)
        results = []
        results << node.location if node.class.name.downcase.include?(query.downcase)
        node.child_nodes.compact.each { |child| results.concat(find_nodes(child, query)) }
        results
      end
    end

    class ListTodos < Base
      tool_name        "list_todos"
      tool_description "Find all TODO/FIXME/HACK/NOTE/OPTIMIZE comments across the codebase."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      path: { type: "string", description: "Directory to search (default: project root)" }
                    },
                    required: []
                  })

      def call(args, context: {})
        root = context[:root] || Dir.pwd
        dir  = args["path"] ? File.expand_path(args["path"], root) : root

        rg = SearchBackend.rg_executable
        out = if rg
                `#{rg} -n --no-heading 'TODO|FIXME|HACK|NOTE|OPTIMIZE' #{Shellwords.shellescape(dir)}`.lines
              else
                `grep -rn 'TODO\\|FIXME\\|HACK\\|NOTE\\|OPTIMIZE' #{Shellwords.shellescape(dir)}`.lines
              end

        return "No TODO/FIXME/HACK/NOTE/OPTIMIZE comments found" if out.empty?

        out.first(100).map(&:strip).join("\n") + (out.size > 100 ? "\n...[#{out.size - 100} more]" : "")
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end

    EnhancedRegistry.register(SearchSymbols)
    EnhancedRegistry.register(FindReferences)
    EnhancedRegistry.register(GrepAst)
    EnhancedRegistry.register(ListTodos)
  end
end

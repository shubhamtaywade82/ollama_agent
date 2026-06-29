# frozen_string_literal: true

require_relative "base"
require_relative "enhanced_registry"

module OllamaAgent
  module Tools
    class GetDefinition < Base
      tool_name        "get_definition"
      tool_description "Jump to the definition of a Ruby method, class, or constant. Returns file + source."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      symbol: { type: "string", description: "Symbol name (method, class, module, constant)" },
                      kind: {
                        type: "string",
                        enum: %w[auto class module method constant],
                        description: "Kind of symbol (default: auto-detect)"
                      }
                    },
                    required: ["symbol"]
                  })

      def call(args, context: {})
        root    = context[:root] || Dir.pwd
        symbol  = args["symbol"].to_s
        kind    = args["kind"] || "auto"

        idx = RubyIndex.build(root: root)

        records = case kind
                  when "class"    then idx.search_class(symbol)
                  when "module"   then idx.search_module(symbol)
                  when "constant" then idx.search_class_or_module(symbol)
                  when "method"   then idx.search_method(symbol)
                  when "auto"
                    idx.search_method(symbol) + idx.search_class_or_module(symbol)
                  else return "Error: unknown kind #{kind}"
                  end

        exact = records.select { |r| r[:name] == symbol }
        record = exact.first || records.first
        return "No definition found for #{symbol.inspect}" unless record

        file = record[:file]
        line = record[:line]
        rel  = file.delete_prefix("#{root}/")

        source = File.readlines(file)
        start_idx = line - 1
        end_idx = find_body_end(source, start_idx)

        {
          file: rel,
          line: line,
          kind: record[:kind],
          name: record[:name],
          source: source[start_idx..end_idx].join.strip
        }
      rescue StandardError => e
        { error: e.message }
      end

      private

      def find_body_end(lines, start)
        depth = 0
        started = false
        (start...lines.size).each do |i|
          line = lines[i]
          started = true if line =~ /\s*(def |class |module |private|public)/
          next unless started

          depth += line.scan(/\bend\b/).size
          return i if depth >= 1 && line =~ /^\s*end\s*$/
        end
        [start + 20, lines.size - 1].min
      end
    end

    class ListDependencies < Base
      tool_name        "list_dependencies"
      tool_description "Return all require/import statements in a file."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      file: { type: "string", description: "File path relative to project root" }
                    },
                    required: ["file"]
                  })

      def call(args, context: {})
        root = context[:root] || Dir.pwd
        file = File.expand_path(args["file"], root)
        return "Error: file not found" unless File.exist?(file)

        src  = File.read(file)
        reqs = src.scan(/require(?:_relative)?\s+['"](.*?)['"]/).flatten
        imports = src.scan(/import\s+(?:\w+\s+from\s+)?['"](.*?)['"]/).flatten
        requires = reqs + imports

        return "No dependencies found" if requires.empty?

        {
          file: args["file"],
          requires: requires
        }
      rescue StandardError => e
        { error: e.message }
      end
    end

    class SummarizeFile < Base
      tool_name        "summarize_file"
      tool_description "Return the public API surface of a file: classes, public methods, constants. Saves context tokens."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      path: { type: "string", description: "File path relative to project root" }
                    },
                    required: ["path"]
                  })

      def call(args, context: {})
        root = context[:root] || Dir.pwd
        file = File.expand_path(args["path"], root)
        return "Error: file not found" unless File.exist?(file)

        src = File.read(file)
        require "prism"
        tree = Prism.parse(src)

        classes  = extract_classes(tree.value)
        methods  = extract_public_methods(tree.value)
        constants = extract_constants(tree.value)

        {
          file: args["path"],
          classes: classes,
          public_methods: methods,
          constants: constants
        }
      rescue LoadError
        "Error: prism gem not available"
      rescue StandardError => e
        { error: e.message }
      end

      private

      def extract_classes(node)
        results = []
        results << node.name.to_s if node.respond_to?(:name) && node.class.name.include?("ClassNode")
        node.child_nodes.compact.each { |c| results.concat(extract_classes(c)) }
        results
      end

      def extract_public_methods(node)
        results = []
        if node.respond_to?(:name) && node.class.name.include?("DefNode")
          results << node.name.to_s
        end
        node.child_nodes.compact.each { |c| results.concat(extract_public_methods(c)) }
        results
      end

      def extract_constants(node)
        results = []
        if node.respond_to?(:name) && node.class.name.include?("ConstantNode")
          results << node.name.to_s
        elsif node.respond_to?(:name) && node.class.name.include?("ConstantWriteNode")
          results << node.name.to_s
        end
        node.child_nodes.compact.each { |c| results.concat(extract_constants(c)) }
        results
      end
    end

    class CheckArchitecture < Base
      tool_name        "check_architecture"
      tool_description "Check a diff against architecture rules. Returns violations array."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      diff: { type: "string", description: "Git diff or code changes to check" },
                      rules_path: { type: "string", description: "Path to architecture rules file (default: CONSTITUTION.md)" }
                    },
                    required: ["diff"]
                  })

      ARCHITECTURE_RULES = [
        { pattern: /require.*active_record|ActiveRecord::Base/, message: "Rails leak: Active Record dependency in non-Rails layer" },
        { pattern: /require.*active_support/, message: "Rails leak: Active Support dependency in non-Rails layer" },
        { pattern: /require.*action_pack|require.*action_controller/, message: "Rails leak: Action Pack dependency outside web layer" },
        { pattern: /# TODO|# FIXME/, message: "New TODO/FIXME introduced without associated issue" },
        { pattern: /binding\.pry|byebug|debugger/, message: "Debugger left in committed code" }
      ].freeze

      def call(args, context: {})
        diff = args["diff"].to_s
        rules_path = args["rules_path"]

        violations = ARCHITECTURE_RULES.filter_map do |rule|
          matches = []
          diff.each_line.with_index(1) do |line, num|
            if line =~ rule[:pattern]
              matches << { line: num, text: line.strip }
            end
          end
          next if matches.empty?

          { rule: rule[:message], matches: matches }
        end

        if rules_path
          root = context[:root] || Dir.pwd
          rf   = File.expand_path(rules_path, root)
          if File.exist?(rf)
            custom = File.read(rf)
            custom.each_line.with_index(1) do |rule_line, i|
              next if rule_line.strip.empty? || rule_line.start_with?("#")
              violations << { rule: "Custom: #{rule_line.strip}" }
            end
          end
        end

        { violations: violations, count: violations.size }
      end
    end

    class GenerateDocs < Base
      tool_name        "generate_docs"
      tool_description "Run YARD documentation generator and return output path."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      path: { type: "string", description: "Path to document (default: lib/)" },
                      format: {
                        type: "string",
                        enum: %w[yard rdoc jsdoc],
                        description: "Documentation format"
                      }
                    },
                    required: []
                  })

      def call(args, context: {})
        root = context[:root] || Dir.pwd
        pt   = Shellwords.shellescape(args["path"] || "lib/")
        fmt  = args["format"] || "yard"

        out = case fmt
              when "yard"  then `cd #{Shellwords.shellescape(root)} && bundle exec yard doc #{pt} 2>&1`
              when "rdoc"  then `cd #{Shellwords.shellescape(root)} && bundle exec rdoc #{pt} 2>&1`
              when "jsdoc" then `cd #{Shellwords.shellescape(root)} && npx jsdoc #{pt} 2>&1`
              else return "Error: unknown format #{fmt}"
              end

        {
          format: fmt,
          exit_code: $?.exitstatus,
          output: out.lines.first(50).join.strip,
          output_dir: fmt == "yard" ? "doc/" : fmt == "rdoc" ? "doc/" : "out/"
        }
      rescue StandardError => e
        { error: e.message }
      end
    end

    EnhancedRegistry.register(GetDefinition)
    EnhancedRegistry.register(ListDependencies)
    EnhancedRegistry.register(SummarizeFile)
    EnhancedRegistry.register(CheckArchitecture)
    EnhancedRegistry.register(GenerateDocs)
  end
end

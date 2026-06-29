# frozen_string_literal: true

require "json"
require_relative "base"
require_relative "enhanced_registry"

module OllamaAgent
  module Tools
    class RunTests < Base
      tool_name        "run_tests"
      tool_description "Run test suite and return structured results. Supports rspec, minitest, jest, pytest."
      tool_risk        :medium
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      pattern: { type: "string", description: "File/pattern to run (default: spec/ or test/)" },
                      framework: {
                        type: "string",
                        enum: %w[rspec minitest jest pytest],
                        description: "Test framework"
                      }
                    },
                    required: []
                  })

      MAX_LINES = 500

      def call(args, context: {})
        root  = context[:root] || Dir.pwd
        pat   = args["pattern"]
        fw    = args["framework"] || detect_framework(root)
        cwd   = root

        cmd = case fw
              when "rspec"    then "bundle exec rspec #{Shellwords.shellescape(pat || "spec/")} --format progress 2>&1"
              when "minitest" then "bundle exec ruby -Ilib:test #{Shellwords.shellescape(pat || "test/")} 2>&1"
              when "jest"     then "npx jest #{pat ? Shellwords.shellescape(pat) : ""} 2>&1"
              when "pytest"   then "python -m pytest #{pat ? Shellwords.shellescape(pat) : ""} 2>&1"
              else return "Error: unknown framework #{fw}"
              end

        out = `#{cmd}`.lines
        exit_code = $?.exitstatus

        {
          framework: fw,
          exit_code: exit_code,
          status: exit_code.zero? ? "pass" : "fail",
          output: out.first(MAX_LINES).join.strip
        }
      rescue StandardError => e
        { error: e.message }
      end

      private

      def detect_framework(root)
        return "rspec"    if File.exist?(File.join(root, "spec"))
        return "minitest" if File.exist?(File.join(root, "test"))
        return "jest"     if File.exist?(File.join(root, "jest.config.js")) || File.exist?(File.join(root, "package.json"))
        return "pytest"   if File.exist?(File.join(root, "pytest.ini")) || File.exist?(File.join(root, "pyproject.toml"))

        "rspec"
      end
    end

    class RunLinter < Base
      tool_name        "run_linter"
      tool_description "Run a linter and return structured violations."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      path: { type: "string", description: "Path to lint (default: .)" },
                      tool: {
                        type: "string",
                        enum: %w[rubocop eslint ruff standardrb],
                        description: "Linter tool"
                      }
                    },
                    required: []
                  })

      MAX_LINES = 200

      def call(args, context: {})
        root = context[:root] || Dir.pwd
        pt   = Shellwords.shellescape(args["path"] || ".")
        tool = args["tool"] || detect_linter(root)

        out = case tool
              when "rubocop"   then `bundle exec rubocop --format simple #{pt} 2>&1`
              when "eslint"    then `npx eslint #{pt} 2>&1`
              when "ruff"      then `ruff check #{pt} 2>&1`
              when "standardrb" then `bundle exec standardrb #{pt} 2>&1`
              else return "Error: unknown linter #{tool}"
              end

        lines = out.lines.first(MAX_LINES)
        {
          tool: tool,
          exit_code: $?.exitstatus,
          violations: lines.size,
          output: lines.join.strip
        }
      rescue StandardError => e
        { error: e.message }
      end

      private

      def detect_linter(root)
        return "rubocop"   if File.exist?(File.join(root, ".rubocop.yml"))
        return "eslint"    if File.exist?(File.join(root, ".eslintrc.js")) || File.exist?(File.join(root, ".eslintrc.json"))
        return "ruff"      if File.exist?(File.join(root, "pyproject.toml")) || File.exist?(File.join(root, "ruff.toml"))
        return "standardrb" if File.exist?(File.join(root, ".standard.yml"))

        "rubocop"
      end
    end

    class RunTypecheck < Base
      tool_name        "run_typecheck"
      tool_description "Run a type checker (steep, sorbet, mypy, tsc) and return type errors."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      path: { type: "string", description: "Path to check (default: .)" },
                      tool: {
                        type: "string",
                        enum: %w[steep sorbet mypy tsc],
                        description: "Type checker"
                      }
                    },
                    required: []
                  })

      def call(args, context: {})
        root = context[:root] || Dir.pwd
        pt   = Shellwords.shellescape(args["path"] || ".")
        tool = args["tool"] || detect_typechecker(root)

        out = case tool
              when "steep"  then `bundle exec steep check #{pt} 2>&1`
              when "sorbet" then `bundle exec srb tc #{pt} 2>&1`
              when "mypy"   then `python -m mypy #{pt} 2>&1`
              when "tsc"    then `npx tsc --noEmit #{pt} 2>&1`
              else return "Error: unknown typechecker #{tool}"
              end

        errors = out.lines.select { |l| l =~ /error:|Error:/ }
        {
          tool: tool,
          exit_code: $?.exitstatus,
          error_count: errors.size,
          output: out.lines.first(200).join.strip
        }
      rescue StandardError => e
        { error: e.message }
      end

      private

      def detect_typechecker(root)
        return "steep"   if File.exist?(File.join(root, "Steepfile"))
        return "sorbet"  if File.exist?(File.join(root, "sorbet/config"))
        return "mypy"    if File.exist?(File.join(root, "mypy.ini")) || File.exist?(File.join(root, "pyproject.toml"))
        return "tsc"     if File.exist?(File.join(root, "tsconfig.json"))

        "steep"
      end
    end

    class RunBenchmark < Base
      tool_name        "run_benchmark"
      tool_description "Execute a benchmark script and return timing results."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      path: { type: "string", description: "Path to benchmark script" },
                      ruby: { type: "string", description: "Ruby command (default: ruby)" }
                    },
                    required: ["path"]
                  })

      def call(args, context: {})
        root   = context[:root] || Dir.pwd
        script = File.expand_path(args["path"], root)
        return "Error: script not found" unless File.exist?(script)

        ruby = args["ruby"] || "ruby"
        out  = `#{ruby} #{Shellwords.shellescape(script)} 2>&1`
        {
          exit_code: $?.exitstatus,
          output: out.lines.first(200).join.strip
        }
      rescue StandardError => e
        { error: e.message }
      end
    end

    class RunCoverage < Base
      tool_name        "run_coverage"
      tool_description "Run test suite with coverage enabled and return coverage summary."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      framework: {
                        type: "string",
                        enum: %w[rspec minitest],
                        description: "Test framework"
                      }
                    },
                    required: []
                  })

      def call(args, context: {})
        root = context[:root] || Dir.pwd
        fw   = args["framework"] || "rspec"

        out = case fw
              when "rspec"
                `COVERAGE=1 bundle exec rspec --format progress 2>&1`
              when "minitest"
                `COVERAGE=1 bundle exec ruby -Ilib:test test/ 2>&1`
              else return "Error: unknown framework #{fw}"
              end

        cov_file = File.join(root, "coverage", ".last_run.json")
        coverage = if File.exist?(cov_file)
                     JSON.parse(File.read(cov_file))["result"] rescue nil
                   end

        {
          framework: fw,
          coverage: coverage,
          output: out.lines.first(100).join.strip
        }
      rescue StandardError => e
        { error: e.message }
      end
    end

    EnhancedRegistry.register(RunTests)
    EnhancedRegistry.register(RunLinter)
    EnhancedRegistry.register(RunTypecheck)
    EnhancedRegistry.register(RunBenchmark)
    EnhancedRegistry.register(RunCoverage)
  end
end

# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"

require_relative "../agent"
require_relative "../patch_risk"

module OllamaAgent
  module SelfImprovement
    # Copies the project into a temp directory, runs the agent with optional semi-auto patch policy,
    # runs the test suite in the sandbox, and optionally merges changed files back to the source tree.
    # rubocop:disable Metrics/ClassLength -- orchestration + restore + merge helpers
    class Improver
      SANDBOX_EXCLUDE = %w[.git vendor coverage tmp .bundle .cursor node_modules .rspec_status].freeze

      # Basenames never merged back from the sandbox (test runs create these; they are gitignored).
      MERGE_SKIP_BASENAMES = %w[.rspec_status].freeze

      FIX_PROMPT = <<~PROMPT
        You are improving the ollama_agent Ruby gem in this temporary sandbox copy.
        Use list_files, search_code, and read_file to understand the code, then edit_file with valid unified diffs.
        Prefer small, reviewable changes: fixes, tests, docs, and clarity.
        Minimal diffs only: fewest lines per edit_file, exact @@ counts—no whole-method or mega-hunks.
        Do not delete Gemfile, Gemfile.lock, the gemspec, or exe/; the improve run restores those from the source
        tree before tests, but deleting them breaks the session.
        Do not add or rely on .rspec_status or other ignored test-artifact files; RSpec may create them during the test step.

        When finished, summarize what you changed in plain language.
      PROMPT

      # rubocop:disable Metrics/ParameterLists -- mirrors CLI; keeps call sites explicit
      # rubocop:disable Metrics/MethodLength
      def run(model: nil, root: nil, yes: false, semi: true, apply: false, http_timeout: nil, think: nil, client: nil)
        source_root = resolve_source_root(root)
        sandbox_root = Dir.mktmpdir("ollama_agent_improve_")
        policy = semi ? PatchRisk.method(:assess).to_proc : nil

        begin
          copy_project_into_sandbox(source_root, sandbox_root)
          run_agent_session(
            sandbox_root,
            client: client,
            model: model,
            confirm_patches: !yes,
            patch_policy: policy,
            http_timeout: http_timeout,
            think: think
          )
          restore_build_essentials_from_source(source_root, sandbox_root)
          missing = missing_gemfile_failure(source_root, sandbox_root)
          return build_run_result(missing, [], source_root) if missing

          test_result = run_test_suite(sandbox_root)
          copied = copy_back_if_requested(test_result, apply, sandbox_root, source_root)
          build_run_result(test_result, copied, source_root)
        ensure
          FileUtils.remove_entry(sandbox_root) if sandbox_root && Dir.exist?(sandbox_root)
        end
      end
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/ParameterLists

      private

      def run_agent_session(sandbox_root, **)
        agent = Agent.new(root: sandbox_root, **)
        agent.run(FIX_PROMPT)
      end

      def copy_back_if_requested(test_result, apply, sandbox_root, source_root)
        return [] unless test_result[:success] && apply

        merge_sandbox_into_source(sandbox_root, source_root)
      end

      def build_run_result(test_result, copied, source_root)
        {
          success: test_result[:success],
          test_output: test_result[:output],
          copied_to_source: copied,
          source_root: source_root
        }
      end

      def copy_project_into_sandbox(source, dest)
        Dir.children(source).each do |entry|
          next if SANDBOX_EXCLUDE.include?(entry)

          FileUtils.cp_r(File.join(source, entry), File.join(dest, entry))
        end
      end

      def resolve_source_root(root)
        start_dir = normalize_improve_root(root)
        nearest = nearest_directory_with_gemfile(start_dir)
        nearest || start_dir
      end

      def normalize_improve_root(root)
        return default_improve_source_root if root.nil? || root.to_s.strip.empty?

        File.expand_path(root)
      end

      # Installed gems omit Gemfile (see gemspec); gem_root may not contain one. Prefer cwd / env from CLI.
      def default_improve_source_root
        from_cwd = nearest_directory_with_gemfile(Dir.pwd)
        return from_cwd if from_cwd

        from_gem = nearest_directory_with_gemfile(OllamaAgent.gem_root)
        return from_gem if from_gem

        OllamaAgent.gem_root
      end

      def nearest_directory_with_gemfile(start_dir)
        dir = File.expand_path(start_dir)
        loop do
          return dir if File.file?(File.join(dir, "Gemfile"))

          parent = File.dirname(dir)
          return nil if parent == dir

          dir = parent
        end
      end

      def missing_gemfile_failure(source_root, sandbox_root)
        return nil if File.file?(File.join(sandbox_root, "Gemfile"))

        msg = <<~MSG
          Cannot run tests: Gemfile is missing in the sandbox after restore from #{source_root}.
          Run `improve` from your project checkout, set OLLAMA_AGENT_ROOT, or pass --root to a tree that contains a Gemfile.
          (The packaged gem does not ship a Gemfile; cwd is used when gem_root has none.)
        MSG
        { success: false, output: msg.strip }
      end

      # The model may delete or corrupt Gemfile / lock / gemspec during edit_file; bundle needs them in the sandbox.
      def restore_build_essentials_from_source(source, sandbox)
        %w[Gemfile Gemfile.lock Rakefile .ruby-version].each do |name|
          src = File.join(source, name)
          next unless File.file?(src)

          FileUtils.cp(src, File.join(sandbox, name))
        end

        Dir.glob(File.join(source, "*.gemspec")).each do |src|
          FileUtils.cp(src, File.join(sandbox, File.basename(src)))
        end
      end

      def run_test_suite(dir)
        output, status = bundle_exec(dir, "rspec", "spec/")
        return { success: true, output: output } if status.success?

        install_out, install_status = bundle_install(dir)
        combined = "#{install_out}\n#{output}"
        return { success: false, output: combined } unless install_status.success?

        output2, status2 = bundle_exec(dir, "rspec", "spec/")
        { success: status2.success?, output: "#{combined}\n#{output2}" }
      end

      def bundle_env(dir)
        { "BUNDLE_GEMFILE" => File.expand_path(File.join(dir, "Gemfile")) }
      end

      def bundle_exec(dir, *)
        Open3.capture2e(bundle_env(dir), "bundle", "exec", *, chdir: dir)
      end

      def bundle_install(dir)
        Open3.capture2e(bundle_env(dir), "bundle", "install", chdir: dir)
      end

      # rubocop:disable Metrics/MethodLength -- straight-line file copy loop
      def merge_sandbox_into_source(sandbox, source)
        paths = []
        each_relative_file(sandbox) do |rel|
          next if MERGE_SKIP_BASENAMES.include?(File.basename(rel))

          src = File.join(sandbox, rel)
          dst = File.join(source, rel)
          next unless File.file?(src)
          next unless file_differs?(src, dst)

          FileUtils.mkdir_p(File.dirname(dst))
          FileUtils.cp(src, dst)
          paths << rel
        end
        paths
      end
      # rubocop:enable Metrics/MethodLength

      def each_relative_file(base)
        base_path = Pathname.new(base)
        Dir.glob(File.join(base, "**", "*"), File::FNM_DOTMATCH).each do |abs|
          next if File.directory?(abs)
          next if abs.include?("#{File::SEPARATOR}vendor#{File::SEPARATOR}")
          next if abs.include?("#{File::SEPARATOR}.git#{File::SEPARATOR}")

          rel = Pathname(abs).relative_path_from(base_path).to_s
          yield rel
        end
      end

      def file_differs?(sandbox_file, target_file)
        return true unless File.file?(target_file)

        File.binread(sandbox_file) != File.binread(target_file)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

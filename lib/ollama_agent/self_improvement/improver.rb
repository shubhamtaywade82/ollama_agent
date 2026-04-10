# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"

require_relative "../agent"
require_relative "../patch_risk"
require_relative "ruby_mastery_context"
require_relative "../streaming/console_streamer"

module OllamaAgent
  module SelfImprovement
    # Copies the project into a temp directory, runs the agent with optional semi-auto patch policy,
    # runs the test suite in the sandbox, and optionally merges changed files back to the source tree.
    # rubocop:disable Metrics/ClassLength -- orchestration + restore + merge helpers
    class Improver
      SANDBOX_EXCLUDE = %w[.git vendor coverage tmp .bundle .cursor node_modules .rspec_status].freeze

      # Basenames never merged back from the sandbox (test runs create these; they are gitignored).
      MERGE_SKIP_BASENAMES = %w[.rspec_status].freeze

      VERIFY_STEPS = %w[syntax rubocop rspec].freeze

      FIX_PROMPT = <<~PROMPT
        You are improving the ollama_agent Ruby gem in this temporary sandbox copy.
        The user message may begin with "## Static analysis (ruby_mastery)" from tooling; confirm against the sandbox.
        Use list_files, search_code, and read_file to understand the code, then edit_file with valid unified diffs.
        Prefer small, reviewable changes: fixes, tests, docs, and clarity.
        Scan for TODO/FIXME/HACK comments and prioritize sensible cleanups when they are low-risk.
        Minimal diffs only: fewest lines per edit_file, exact @@ counts—no whole-method or mega-hunks.
        Do not delete Gemfile, Gemfile.lock, the gemspec, or exe/; the improve run restores those from the source
        tree before tests, but deleting them breaks the session.
        Do not add or rely on .rspec_status or other ignored test-artifact files; RSpec may create them during the test step.
        After this session, the runner verifies the sandbox (configured steps such as ruby -c on changed .rb files,
        optional RuboCop, then bundle exec rspec spec/)—keep edits syntactically valid and test-friendly.

        When finished, summarize what you changed in plain language.
      PROMPT

      # rubocop:disable Metrics/ParameterLists -- mirrors CLI; keeps call sites explicit
      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- single orchestration entrypoint
      def run(model: nil, root: nil, yes: false, semi: true, apply: false, http_timeout: nil, think: nil, client: nil,
              skill_paths: nil, skills_enabled: nil, skills_include: nil, skills_exclude: nil,
              external_skills_enabled: nil,
              max_tokens: nil, context_summarize: nil,
              stream: false,
              verify: nil,
              ruby_mastery: true)
        source_root = resolve_source_root(root)
        sandbox_root = Dir.mktmpdir("ollama_agent_improve_")
        policy = semi ? PatchRisk.method(:assess).to_proc : nil
        verify_steps = normalize_verify_steps(verify)

        begin
          copy_project_into_sandbox(source_root, sandbox_root)
          run_agent_session(
            sandbox_root,
            source_root: source_root,
            ruby_mastery: ruby_mastery,
            stream: stream,
            client: client,
            model: model,
            confirm_patches: !yes,
            patch_policy: policy,
            http_timeout: http_timeout,
            think: think,
            max_tokens: max_tokens,
            context_summarize: context_summarize,
            skill_paths: skill_paths,
            skills_enabled: skills_enabled,
            skills_include: skills_include,
            skills_exclude: skills_exclude,
            external_skills_enabled: external_skills_enabled
          )
          restore_build_essentials_from_source(source_root, sandbox_root)
          missing = missing_gemfile_failure(source_root, sandbox_root)
          return build_run_result(missing, [], source_root) if missing

          test_result = run_test_suite(sandbox_root, source_root, verify_steps)
          copied = copy_back_if_requested(test_result, apply, sandbox_root, source_root)
          build_run_result(test_result, copied, source_root)
        ensure
          FileUtils.remove_entry(sandbox_root) if sandbox_root && Dir.exist?(sandbox_root)
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
      # rubocop:enable Metrics/ParameterLists

      private

      def run_agent_session(sandbox_root, source_root:, ruby_mastery: true, **kwargs)
        stream = kwargs.delete(:stream) { false }
        agent = Agent.new(root: sandbox_root, **kwargs)
        Streaming::ConsoleStreamer.new.attach(agent.hooks) if stream
        agent.run(improve_user_prompt(source_root, ruby_mastery))
      end

      def improve_user_prompt(source_root, use_ruby_mastery)
        return FIX_PROMPT unless use_ruby_mastery

        preamble = RubyMasteryContext.markdown_section(source_root).to_s.strip
        return FIX_PROMPT if preamble.empty?

        "#{preamble}\n\n#{FIX_PROMPT}"
      end

      def normalize_verify_steps(verify_param)
        tokens = split_verify_tokens(resolve_verify_raw(verify_param))
        warn_unknown_verify_tokens(tokens)
        ordered = VERIFY_STEPS.select { |step| tokens.include?(step) }
        return ["rspec"] if ordered.empty?

        ordered
      end

      def resolve_verify_raw(verify_param)
        raw = verify_param.to_s.strip
        return ENV.fetch("OLLAMA_AGENT_IMPROVE_VERIFY", "rspec") if raw.empty?

        raw
      end

      def split_verify_tokens(raw)
        raw.split(",").map { |s| s.strip.downcase }.reject(&:empty?)
      end

      def warn_unknown_verify_tokens(tokens)
        tokens.each do |t|
          next if VERIFY_STEPS.include?(t)

          warn "ollama_agent improve: unknown verify step #{t.inspect} (ignored)"
        end
      end

      def run_test_suite(sandbox_root, source_root, verify_steps)
        segments = []
        verify_steps.each do |step|
          seg = run_verify_step(step, sandbox_root, source_root)
          segments << seg[:label_output]
          return verification_failure(segments) unless seg[:success]
        end
        { success: true, output: segments.join("\n\n") }
      end

      def run_verify_step(step, sandbox_root, source_root)
        label_result = verify_step_pair(step, sandbox_root, source_root)
        label, result = label_result
        return { success: true, label_output: "" } unless label

        { success: result[:success], label_output: "#{label}#{result[:output]}" }
      end

      def verify_step_pair(step, sandbox_root, source_root)
        case step
        when "syntax"
          ["=== syntax (ruby -c) ===\n", run_changed_ruby_syntax_check(sandbox_root, source_root)]
        when "rubocop"
          ["=== rubocop ===\n", run_bundle_tool(sandbox_root, "rubocop")]
        when "rspec"
          ["=== rspec ===\n", run_bundle_rspec(sandbox_root)]
        else
          [nil, nil]
        end
      end

      def verification_failure(segments)
        { success: false, output: segments.join("\n\n") }
      end

      def run_changed_ruby_syntax_check(sandbox_root, source_root)
        outs = []
        each_changed_ruby_file(sandbox_root, source_root) do |rel|
          abs = File.join(sandbox_root, rel)
          out, status = Open3.capture2e("ruby", "-c", abs)
          outs << out.to_s.strip
          return { success: false, output: outs.join("\n") } unless status.success?
        end
        { success: true, output: outs.empty? ? "(no changed .rb files)" : outs.join("\n") }
      end

      def each_changed_ruby_file(sandbox_root, source_root)
        each_relative_file(sandbox_root) do |rel|
          next unless rel.end_with?(".rb")

          yield rel if file_differs?(File.join(sandbox_root, rel), File.join(source_root, rel))
        end
      end

      def run_bundle_rspec(dir)
        run_bundle_tool(dir, "rspec", "spec/")
      end

      def run_bundle_tool(dir, tool, *)
        output, status = bundle_exec(dir, tool, *)
        return { success: true, output: output } if status.success?

        install_out, install_status = bundle_install(dir)
        combined = "#{install_out}\n#{output}"
        return { success: false, output: combined } unless install_status.success?

        output2, status2 = bundle_exec(dir, tool, *)
        { success: status2.success?, output: "#{combined}\n#{output2}" }
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

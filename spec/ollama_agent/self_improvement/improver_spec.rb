# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::SelfImprovement::Improver do
  let(:source) { Dir.mktmpdir }
  let(:sandbox) { Dir.mktmpdir }
  let(:improver) { described_class.new }

  after do
    FileUtils.remove_entry(source)
    FileUtils.remove_entry(sandbox)
  end

  describe "#restore_build_essentials_from_source" do
    it "overwrites Gemfile in the sandbox from the source tree" do
      File.write(File.join(source, "Gemfile"), "source 'https://rubygems.org'\n")
      File.write(File.join(sandbox, "Gemfile"), "broken")

      improver.send(:restore_build_essentials_from_source, source, sandbox)

      expect(File.read(File.join(sandbox, "Gemfile"))).to include("rubygems.org")
    end

    it "copies gemspec files from the source tree" do
      File.write(File.join(source, "foo.gemspec"), "Gem::Specification.new { |s| s.name = 'foo' }")
      improver.send(:restore_build_essentials_from_source, source, sandbox)
      expect(File).to be_file(File.join(sandbox, "foo.gemspec"))
    end
  end

  describe "#resolve_source_root" do
    it "treats a blank root like the default gem root" do
      expect(improver.send(:resolve_source_root, "")).to eq(OllamaAgent.gem_root)
      expect(improver.send(:resolve_source_root, "   ")).to eq(OllamaAgent.gem_root)
    end

    it "uses the working tree when the loaded gem_root has no Gemfile (installed gem layout)" do
      real_root = OllamaAgent.gem_root
      allow(OllamaAgent).to receive(:gem_root).and_return(Dir.mktmpdir)

      Dir.chdir(real_root) do
        expect(improver.send(:resolve_source_root, nil)).to eq(File.expand_path(real_root))
      end
    end

    it "walks up from a subdirectory until it finds a Gemfile" do
      nested = File.join(source, "lib", "nested")
      FileUtils.mkdir_p(nested)
      File.write(File.join(source, "Gemfile"), "source 'https://rubygems.org'\n")

      expect(improver.send(:resolve_source_root, nested)).to eq(File.expand_path(source))
    end
  end

  describe "#merge_sandbox_into_source" do
    it "does not copy .rspec_status from the sandbox into the source tree" do
      File.write(File.join(source, "tracked.txt"), "a")
      File.write(File.join(sandbox, "tracked.txt"), "b")
      File.write(File.join(sandbox, ".rspec_status"), "rspec parallel state")

      copied = improver.send(:merge_sandbox_into_source, sandbox, source)

      expect(copied).to eq(["tracked.txt"])
      expect(File.read(File.join(source, "tracked.txt"))).to eq("b")
      expect(File).not_to be_file(File.join(source, ".rspec_status"))
    end
  end

  describe "#missing_gemfile_failure" do
    it "returns nil when the sandbox already has a Gemfile" do
      File.write(File.join(sandbox, "Gemfile"), "gem 'rake'\n")
      expect(improver.send(:missing_gemfile_failure, source, sandbox)).to be_nil
    end

    it "returns a failure hash when the sandbox has no Gemfile" do
      out = improver.send(:missing_gemfile_failure, source, sandbox)
      expect(out[:success]).to be(false)
      expect(out[:output]).to include("Gemfile is missing")
      expect(out[:output]).to include(source)
    end
  end

  describe "#run" do
    let(:fake_sandbox) { Dir.mktmpdir }

    after do
      FileUtils.remove_entry(fake_sandbox) if fake_sandbox && Dir.exist?(fake_sandbox)
    end

    it "accepts max_tokens, context_summarize, stream, and verify without ArgumentError" do
      File.write(File.join(source, "Gemfile"), "source 'https://rubygems.org'\n")
      allow(Dir).to receive(:mktmpdir).and_wrap_original do |meth, *args|
        args == ["ollama_agent_improve_"] ? fake_sandbox : meth.call(*args)
      end
      allow(improver).to receive(:copy_project_into_sandbox)
      allow(improver).to receive(:run_agent_session)
      allow(improver).to receive(:restore_build_essentials_from_source)
      allow(improver).to receive_messages(missing_gemfile_failure: nil,
                                          run_test_suite: { success: true, output: "ok" }, copy_back_if_requested: [])

      result = improver.run(
        root: source,
        max_tokens: 12_000,
        context_summarize: true,
        stream: true,
        verify: "rspec"
      )

      expect(result[:success]).to be(true)
      expect(improver).to have_received(:run_agent_session).with(
        fake_sandbox,
        hash_including(
          max_tokens: 12_000,
          context_summarize: true,
          stream: true,
          source_root: source,
          ruby_mastery: true
        )
      )
    end
  end

  describe "verify step parsing" do
    it "uses OLLAMA_AGENT_IMPROVE_VERIFY when the verify argument is blank" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("OLLAMA_AGENT_IMPROVE_VERIFY", "rspec").and_return("syntax,rubocop")

      expect(improver.send(:normalize_verify_steps, "")).to eq(%w[syntax rubocop])
    end

    it "orders steps as syntax, rubocop, rspec regardless of token order" do
      expect(improver.send(:normalize_verify_steps, "rspec,syntax,rubocop")).to eq(%w[syntax rubocop rspec])
    end

    it "falls back to rspec when every token is unknown" do
      steps = nil
      expect { steps = improver.send(:normalize_verify_steps, "bogus,nope") }.to output(/unknown verify/).to_stderr
      expect(steps).to eq(["rspec"])
    end
  end

  describe "#run_changed_ruby_syntax_check" do
    it "succeeds when no .rb files differ between sandbox and source" do
      FileUtils.mkdir_p(File.join(source, "lib"))
      File.write(File.join(source, "lib", "a.rb"), "def x; end\n")
      FileUtils.mkdir_p(File.join(sandbox, "lib"))
      File.write(File.join(sandbox, "lib", "a.rb"), "def x; end\n")

      result = improver.send(:run_changed_ruby_syntax_check, sandbox, source)

      expect(result[:success]).to be(true)
      expect(result[:output]).to include("no changed")
    end

    it "fails when a changed .rb file is not valid Ruby" do
      FileUtils.mkdir_p(File.join(source, "lib"))
      File.write(File.join(source, "lib", "a.rb"), "def ok; end\n")
      FileUtils.mkdir_p(File.join(sandbox, "lib"))
      File.write(File.join(sandbox, "lib", "a.rb"), "def ok(")

      result = improver.send(:run_changed_ruby_syntax_check, sandbox, source)

      expect(result[:success]).to be(false)
    end
  end
end

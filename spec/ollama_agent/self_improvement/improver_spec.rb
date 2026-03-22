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
end

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
end

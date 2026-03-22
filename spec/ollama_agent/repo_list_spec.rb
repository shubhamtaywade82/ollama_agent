# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OllamaAgent::RepoList" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:agent) { OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false) }

  after do
    FileUtils.remove_entry(tmpdir)
  end

  describe "#list_files" do
    it "returns sorted relative paths and skips .git" do
      FileUtils.mkdir_p(File.join(tmpdir, "lib", "foo"))
      File.write(File.join(tmpdir, "lib", "foo", "a.rb"), "1")
      File.write(File.join(tmpdir, "README.md"), "x")
      FileUtils.mkdir_p(File.join(tmpdir, ".git", "objects"))
      File.write(File.join(tmpdir, ".git", "config"), "x")

      out = agent.send(:list_files, ".", 50)
      expect(out).to include("README.md")
      expect(out).to include("lib/foo/a.rb")
      expect(out).not_to include(".git/")
    end

    it "notes when the result is truncated at the cap" do
      File.write(File.join(tmpdir, "a.rb"), "1")
      File.write(File.join(tmpdir, "b.rb"), "2")
      File.write(File.join(tmpdir, "c.rb"), "3")

      out = agent.send(:list_files, ".", 2)
      expect(out).to include("truncated at 2 entries")
    end
  end
end

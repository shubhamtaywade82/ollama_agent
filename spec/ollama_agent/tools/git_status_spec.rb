# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::GitStatus do
  let(:tmpdir) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(tmpdir)
  end

  before do
    system("git", "init", "-q", chdir: tmpdir)
    File.write(File.join(tmpdir, "untracked.txt"), "x")
  end

  it "runs git status in the project root from context" do
    output = described_class.new.call({}, context: { root: tmpdir })
    expect(output).to include("untracked.txt")
  end
end

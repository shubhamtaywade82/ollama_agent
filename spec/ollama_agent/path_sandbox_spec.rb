# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::PathSandbox do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmpdir) }

  def allow?(rel)
    root_abs = File.expand_path(tmpdir)
    root_real = File.realpath(root_abs)
    described_class.allowed?(root_abs, root_real, rel)
  end

  it "allows a normal relative path" do
    File.write(File.join(tmpdir, "a.txt"), "x")
    expect(allow?("a.txt")).to be true
  end

  it "rejects traversal via .." do
    expect(allow?("../outside")).to be false
  end

  it "rejects blank path" do
    expect(allow?("")).to be false
    expect(allow?("   ")).to be false
  end

  it "rejects a symlink under root that points outside", unless: Gem.win_platform? do
    outside = Dir.mktmpdir
    link = File.join(tmpdir, "escape")
    File.symlink(outside, link)
    expect(allow?("escape")).to be false
    expect(allow?("escape/secret")).to be false
  ensure
    FileUtils.remove_entry(outside)
  end

  it "allows a planned path under root when intermediate dirs do not exist yet" do
    expect(allow?("newdir/newfile.txt")).to be true
  end

  it "returns false for a symlink loop without raising", unless: Gem.win_platform? do
    loop_a = File.join(tmpdir, "loop_a")
    loop_b = File.join(tmpdir, "loop_b")
    File.symlink(loop_b, loop_a)
    File.symlink(loop_a, loop_b)
    expect(allow?("loop_a/nested")).to be false
  end
end

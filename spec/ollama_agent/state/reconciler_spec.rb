# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::State::Reconciler do
  it "reports no drift when the observer matches the pre fingerprint" do
    Dir.mktmpdir("recon-ok") do |root|
      calc = instance_double(OllamaAgent::State::WorkspaceFingerprint)
      rec = described_class.new(workspace_root: root, fingerprint_calculator: calc)
      out = rec.reconcile(pre_fingerprint: "a", post_state_observer: -> { "a" })
      expect(out[:fingerprint_drifted]).to be(false)
      expect(out[:changed_files]).to eq([])
      expect(out[:conflicts]).to eq([])
    end
  end

  it "returns an empty changed file list when git is unavailable but fingerprints differ" do
    Dir.mktmpdir("recon-nogit") do |root|
      calc = instance_double(OllamaAgent::State::WorkspaceFingerprint)
      rec = described_class.new(workspace_root: root, fingerprint_calculator: calc)
      out = rec.reconcile(pre_fingerprint: "a", post_state_observer: -> { "b" })
      expect(out[:fingerprint_drifted]).to be(true)
      expect(out[:changed_files]).to eq([])
    end
  end

  it "enumerates git porcelain paths when drifted and .git exists" do
    Dir.mktmpdir("recon-git") do |root|
      system("git", "init", chdir: root, out: File::NULL, err: File::NULL)
      File.write(File.join(root, "z.rb"), "z = 1")

      calc = instance_double(OllamaAgent::State::WorkspaceFingerprint)
      rec = described_class.new(workspace_root: root, fingerprint_calculator: calc)
      out = rec.reconcile(pre_fingerprint: "a", post_state_observer: -> { "b" })
      expect(out[:fingerprint_drifted]).to be(true)
      expect(out[:changed_files]).to eq(["z.rb"])
    end
  end
end

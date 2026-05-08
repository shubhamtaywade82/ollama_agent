# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::State::ReentryPacket, ".build" do
  it "uses an empty summary when there is no git repo" do
    Dir.mktmpdir("reentry-no-git") do |root|
      finger = instance_double(OllamaAgent::State::WorkspaceFingerprint, compute: "fp-1")
      summarizer = instance_double(OllamaAgent::State::ASTSummarizer)
      allow(summarizer).to receive(:summarize)

      packet = described_class.build(
        reason: "test",
        workspace_root: root,
        ast_summarizer: summarizer,
        fingerprint_calculator: finger,
        touched_methods: ["m"]
      )

      expect(packet.workspace_fingerprint).to eq("fp-1")
      expect(packet.changed_files).to eq([])
      expect(packet.summary).to eq("{}")
      expect(summarizer).not_to have_received(:summarize)
    end
  end

  it "serializes AST summaries for porcelain paths when .git exists" do
    Dir.mktmpdir("reentry-git") do |root|
      system("git", "init", chdir: root, out: File::NULL, err: File::NULL)
      File.write(File.join(root, "x.rb"), "x = 1")

      finger = instance_double(OllamaAgent::State::WorkspaceFingerprint, compute: "fp-2")
      summarizer = instance_double(OllamaAgent::State::ASTSummarizer)
      allow(summarizer).to receive(:summarize).and_return({ files: { "x.rb" => { ok: true } } })

      packet = described_class.build(
        reason: "test",
        workspace_root: root,
        ast_summarizer: summarizer,
        fingerprint_calculator: finger,
        touched_methods: []
      )

      expect(packet.changed_files).to eq(["x.rb"])
      expect(summarizer).to have_received(:summarize).with(
        file_paths: ["x.rb"],
        touched_methods: []
      )
      expect(JSON.parse(packet.summary)).to eq("files" => { "x.rb" => { "ok" => true } })
    end
  end
end

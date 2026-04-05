# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::PatchSupport do
  let(:tmpdir) { Dir.mktmpdir }
  let(:agent) { OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false) }

  after { FileUtils.remove_entry(tmpdir) }

  it "ends patch_failure_message with a newline" do
    msg = agent.send(:patch_failure_message, "stderr detail", dry_run: true)
    expect(msg).to end_with("\n")
  end
end

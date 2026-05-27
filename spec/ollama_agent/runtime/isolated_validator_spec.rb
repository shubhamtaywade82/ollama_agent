# frozen_string_literal: true

require "spec_helper"
require "securerandom"

RSpec.describe OllamaAgent::Runtime::IsolatedValidator do
  def validator_image
    ENV.fetch("OLLAMA_AGENT_VALIDATOR_IMAGE", "ruby:3.3-slim-bookworm")
  end

  def make_validator(workspace, **kwargs)
    described_class.new(
      image: validator_image,
      workspace_root: workspace,
      timeout_epochs: 60,
      **kwargs
    )
  end

  context "with Docker", :docker do
    it "returns :ok and captures stdout for a simple echo" do
      Dir.mktmpdir("iso-val-ok") do |workspace|
        v = make_validator(workspace)
        result = v.run(
          command: %w[echo hello],
          manifest_id: "m1",
          logical_stamp: "1"
        )
        expect(result[:status]).to eq(:ok)
        expect(result[:exit_code]).to eq(0)
        expect(result[:stdout]).to include("hello")
        expect(result[:image_digest]).to match(/\Asha256:[0-9a-f]{64}\z/i)
      end
    end

    it "does not expand host-shell metacharacters when argv is passed through to the container" do
      Dir.mktmpdir("iso-val-glob") do |workspace|
        v = make_validator(workspace)
        result = v.run(
          command: ["/usr/bin/printf", "%s", "$(echo injected)"],
          manifest_id: "m2",
          logical_stamp: "2"
        )
        expect(result[:status]).to eq(:ok)
        expect(result[:stdout]).to eq("$(echo injected)")
      end
    end

    it "returns :runtime_unavailable when the runtime executable cannot be resolved" do
      Dir.mktmpdir("iso-val-rt") do |workspace|
        v = make_validator(workspace, runtime_command: "no_such_runtime_#{SecureRandom.hex(4)}")
        result = v.run(command: ["/bin/true"], manifest_id: "m4", logical_stamp: "4")
        expect(result[:status]).to eq(:runtime_unavailable)
        expect(result[:exit_code]).to be_nil
      end
    end
  end

  it "rejects a String command with ArgumentError before touching the runtime" do
    Dir.mktmpdir("iso-val-arg") do |workspace|
      v = described_class.new(
        image: "unused",
        workspace_root: workspace,
        runtime_command: "docker"
      )
      expect do
        v.run(command: "/bin/echo hi", manifest_id: "m3", logical_stamp: "3")
      end.to raise_error(ArgumentError, /Array<String>/)
    end
  end
end

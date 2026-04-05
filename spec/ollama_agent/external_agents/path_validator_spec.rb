# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/ollama_agent/external_agents/path_validator"

RSpec.describe OllamaAgent::ExternalAgents::PathValidator do
  let(:root) { Dir.mktmpdir }

  after { FileUtils.remove_entry(root) }

  describe ".validate_within_root!" do
    it "allows paths under the root" do
      expect do
        described_class.validate_within_root!(root, ["README.md"])
      end.not_to raise_error
    end

    it "raises a generic error without embedding the rejected path" do
      expect do
        described_class.validate_within_root!(root, ["../../../etc/passwd"])
      end.to raise_error(ArgumentError, "path outside project root")
    end

    it "logs the path when OLLAMA_AGENT_DEBUG is set" do
      ENV["OLLAMA_AGENT_DEBUG"] = "1"
      expect do
        described_class.validate_within_root!(root, ["../../../etc/passwd"])
      end.to output(/PathValidator rejected path/).to_stderr.and raise_error(ArgumentError)
    ensure
      ENV.delete("OLLAMA_AGENT_DEBUG")
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::OpenPullRequest do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("open_pull_request")
    end

    it "is high risk and requires approval" do
      expect(tool.risk_level).to eq(:high)
      expect(tool.requires_approval).to be(true)
    end

    it "is not read_only safe" do
      expect(tool.read_only_safe).to be(false)
    end
  end

  describe "#call" do
    it "returns error when GITHUB_TOKEN is not set" do
      orig = ENV.delete("GITHUB_TOKEN")
      result = tool.call({ "title" => "Test PR" }, context: { root: Dir.pwd })
      expect(result).to match(/GITHUB_TOKEN/)
    ensure
      ENV["GITHUB_TOKEN"] = orig
    end

    it "is blocked in read-only mode" do
      env_was = ENV.fetch("GITHUB_TOKEN", nil)
      ENV["GITHUB_TOKEN"] = "test_token"
      result = tool.call({ "title" => "x" }, context: { root: Dir.pwd, read_only: true })
      expect(result).to match(/read-only/)
    ensure
      ENV["GITHUB_TOKEN"] = env_was
    end
  end
end

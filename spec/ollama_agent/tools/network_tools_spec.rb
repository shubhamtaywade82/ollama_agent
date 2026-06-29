# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::GithubComment do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("github_comment")
    end

    it "is medium risk and requires approval" do
      expect(tool.risk_level).to eq(:medium)
      expect(tool.requires_approval).to be(true)
    end

    it "is not read_only safe" do
      expect(tool.read_only_safe).to be(false)
    end
  end

  describe "#call" do
    it "returns error when GITHUB_TOKEN is not set" do
      orig = ENV.delete("GITHUB_TOKEN")
      result = tool.call({ "repo" => "x/y", "pr_number" => 1, "body" => "hi" }, context: {})
      expect(result).to match(/GITHUB_TOKEN/)
    ensure
      ENV["GITHUB_TOKEN"] = orig
    end

    it "is blocked in read-only mode" do
      env_was = ENV.fetch("GITHUB_TOKEN", nil)
      ENV["GITHUB_TOKEN"] = "x"
      result = tool.call({ "repo" => "x/y", "pr_number" => 1, "body" => "hi" }, context: { read_only: true })
      expect(result).to match(/read-only/)
    ensure
      ENV["GITHUB_TOKEN"] = env_was
    end
  end
end

RSpec.describe OllamaAgent::Tools::FetchUrl do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("fetch_url")
    end

    it "is read_only safe" do
      expect(tool.read_only_safe).to be(true)
    end
  end

  describe "#call" do
    before { allow(Net::HTTP).to receive(:get_response).and_raise(SocketError, "mock") }

    it "returns error on network failure" do
      result = tool.call({ "url" => "http://example.com/test" }, context: {})
      expect(result).to be_a(Hash)
      expect(result).to have_key(:error)
    end
  end
end

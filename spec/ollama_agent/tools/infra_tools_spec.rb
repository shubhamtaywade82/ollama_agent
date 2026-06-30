# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::DockerRun do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("docker_run")
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
    it "is blocked in read-only mode" do
      result = tool.call({ "image" => "alpine", "command" => "echo hi" }, context: { read_only: true })
      expect(result).to match(/read-only/)
    end
  end
end

RSpec.describe OllamaAgent::Tools::CiTrigger do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("ci_trigger")
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
      result = tool.call({ "workflow" => "ci.yml", "repo" => "x/y" }, context: {})
      expect(result).to match(/GITHUB_TOKEN/)
    ensure
      ENV["GITHUB_TOKEN"] = orig
    end
  end
end

RSpec.describe OllamaAgent::Tools::ReadCiLogs do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("read_ci_logs")
    end

    it "is read_only safe" do
      expect(tool.read_only_safe).to be(true)
    end
  end

  describe "#call" do
    it "returns error when GITHUB_TOKEN is not set" do
      orig = ENV.delete("GITHUB_TOKEN")
      result = tool.call({ "repo" => "x/y", "run_id" => 1 }, context: {})
      expect(result).to match(/GITHUB_TOKEN/)
    ensure
      ENV["GITHUB_TOKEN"] = orig
    end
  end
end

RSpec.describe OllamaAgent::Tools::EnvGet do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("env_get")
    end

    it "is read_only safe" do
      expect(tool.read_only_safe).to be(true)
    end
  end

  describe "#call" do
    it "returns the value of an allowlisted env var" do
      orig = ENV["HOME"]
      ENV["HOME"] = "/home/test"
      result = tool.call({ "key" => "HOME" }, context: {})
      expect(result).to eq("/home/test")
    ensure
      ENV["HOME"] = orig
    end

    it "returns a message when the var is not set" do
      orig = ENV.delete("OLLAMA_AGENT_LOG_LEVEL")
      result = tool.call({ "key" => "OLLAMA_AGENT_LOG_LEVEL" }, context: {})
      expect(result).to match(/not set/)
    ensure
      ENV["OLLAMA_AGENT_LOG_LEVEL"] = orig
    end
  end
end

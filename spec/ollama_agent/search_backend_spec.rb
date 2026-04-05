# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tempfile"
require_relative "../../lib/ollama_agent/search_backend"

RSpec.describe OllamaAgent::SearchBackend do
  before { described_class.clear_cache! }

  after { described_class.clear_cache! }

  describe ".rg_executable" do
    it "uses OLLAMA_AGENT_RG_PATH when it points to an executable file" do
      stub = Tempfile.new("fake_rg")
      stub.close
      File.chmod(0o755, stub.path)
      ENV["OLLAMA_AGENT_RG_PATH"] = stub.path
      expect(described_class.rg_executable).to eq(File.realpath(stub.path))
    ensure
      ENV.delete("OLLAMA_AGENT_RG_PATH")
      File.unlink(stub.path) if stub && File.exist?(stub.path)
    end

    it "returns nil when command -v fails", :aggregate_failures do
      allow(Open3).to receive(:capture2).with("command", "-v", "rg").and_return(["", double(success?: false)])
      expect(described_class.rg_executable).to be_nil
    end
  end
end

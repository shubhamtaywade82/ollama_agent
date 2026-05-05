# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::AgentRootResolver do
  describe ".resolve" do
    it "expands a relative path from cwd" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(described_class.resolve("sub", cwd: dir, env: {})).to eq(File.join(dir, "sub"))
        end
      end
    end

    it "uses OLLAMA_AGENT_ROOT from env when explicit root is nil" do
      Dir.mktmpdir do |dir|
        env = { "OLLAMA_AGENT_ROOT" => File.join(dir, "w") }
        FileUtils.mkdir_p(env["OLLAMA_AGENT_ROOT"])
        expect(described_class.resolve(nil, cwd: dir, env: env)).to eq(env["OLLAMA_AGENT_ROOT"])
      end
    end
  end
end

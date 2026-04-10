# frozen_string_literal: true

RSpec.describe OllamaAgent::ModelEnv do
  describe ".resolved_model_from_env" do
    around do |example|
      previous = ENV.to_hash
      ENV.delete("OLLAMA_AGENT_MODEL")
      ENV.delete("OLLAMA_MODEL")
      example.run
    ensure
      ENV.replace(previous)
    end

    it "returns nil when no model env vars are set" do
      expect(described_class.resolved_model_from_env).to be_nil
    end

    it "returns OLLAMA_AGENT_MODEL when set" do
      ENV["OLLAMA_AGENT_MODEL"] = "gpt-oss:120b"

      expect(described_class.resolved_model_from_env).to eq("gpt-oss:120b")
    end

    it "returns OLLAMA_MODEL when OLLAMA_AGENT_MODEL is unset" do
      ENV["OLLAMA_MODEL"] = "cloud-model"

      expect(described_class.resolved_model_from_env).to eq("cloud-model")
    end
  end

  describe ".default_chat_model" do
    around do |example|
      previous = ENV.to_hash
      ENV.delete("OLLAMA_AGENT_MODEL")
      ENV.delete("OLLAMA_MODEL")
      example.run
    ensure
      ENV.replace(previous)
    end

    it "prefers OLLAMA_AGENT_MODEL over OLLAMA_MODEL" do
      ENV["OLLAMA_AGENT_MODEL"] = "agent-model"
      ENV["OLLAMA_MODEL"] = "ollama-cli-model"

      expect(described_class.default_chat_model).to eq("agent-model")
    end

    it "uses OLLAMA_MODEL when OLLAMA_AGENT_MODEL is unset" do
      ENV["OLLAMA_MODEL"] = "ollama-cli-model"

      expect(described_class.default_chat_model).to eq("ollama-cli-model")
    end

    it "ignores blank OLLAMA_AGENT_MODEL and uses OLLAMA_MODEL" do
      ENV["OLLAMA_AGENT_MODEL"] = "   "
      ENV["OLLAMA_MODEL"] = "fallback"

      expect(described_class.default_chat_model).to eq("fallback")
    end

    it "falls back to Ollama::Config when both env vars are unset" do
      config = instance_double(Ollama::Config, model: "from-config")
      allow(Ollama::Config).to receive(:new).and_return(config)

      expect(described_class.default_chat_model).to eq("from-config")
    end
  end
end

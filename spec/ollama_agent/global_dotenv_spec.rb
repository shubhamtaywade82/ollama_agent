# frozen_string_literal: true

RSpec.describe OllamaAgent::GlobalDotenv do
  describe ".reconcile_after_ollama_client!" do
    let(:key) { "OLLAMA_AGENT_DOTENV_SPEC_KEY" }

    around do |example|
      previous = ENV.to_hash
      ENV.delete("OLLAMA_AGENT_USE_LOCAL_DOTENV")
      ENV.delete("OLLAMA_AGENT_DOTENV_PATH")
      ENV.delete(key)
      example.run
    ensure
      ENV.replace(previous)
    end

    it "replaces cwd dotenv with values from the global file when OLLAMA_AGENT_DOTENV_PATH is set" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, ".env")
        File.write(path, %(#{key}=from_global\n))

        snapshot = ENV.to_hash
        ENV[key] = "from_cwd"
        ENV["OLLAMA_AGENT_DOTENV_PATH"] = path

        described_class.reconcile_after_ollama_client!(snapshot)

        expect(ENV.fetch(key)).to eq("from_global")
      end
    end

    it "does nothing when OLLAMA_AGENT_USE_LOCAL_DOTENV=1" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, ".env")
        File.write(path, %(#{key}=from_global\n))

        snapshot = ENV.to_hash
        ENV[key] = "from_cwd"
        ENV["OLLAMA_AGENT_DOTENV_PATH"] = path
        ENV["OLLAMA_AGENT_USE_LOCAL_DOTENV"] = "1"

        described_class.reconcile_after_ollama_client!(snapshot)

        expect(ENV.fetch(key)).to eq("from_cwd")
      end
    end

    it "does nothing when the resolved path is missing" do
      snapshot = ENV.to_hash
      ENV[key] = "from_cwd"
      ENV["OLLAMA_AGENT_DOTENV_PATH"] = File.join(Dir.tmpdir, "ollama_agent_dotenv_spec_missing_#{Process.pid}")

      described_class.reconcile_after_ollama_client!(snapshot)

      expect(ENV.fetch(key)).to eq("from_cwd")
    end
  end

  describe ".resolved_path" do
    around do |example|
      previous = ENV.to_hash
      ENV.delete("OLLAMA_AGENT_DOTENV_PATH")
      ENV.delete("XDG_CONFIG_HOME")
      example.run
    ensure
      ENV.replace(previous)
    end

    it "uses XDG_CONFIG_HOME when set" do
      Dir.mktmpdir do |dir|
        ENV["XDG_CONFIG_HOME"] = dir
        expected = File.join(dir, "ollama_agent", ".env")
        expect(described_class.resolved_path).to eq(expected)
      end
    end

    it "falls back to ~/.config when XDG_CONFIG_HOME is unset" do
      expected = File.expand_path(File.join(Dir.home, ".config", "ollama_agent", ".env"))
      expect(described_class.resolved_path).to eq(expected)
    end
  end
end

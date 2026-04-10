# frozen_string_literal: true

require "spec_helper"
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

    it "discovers rg on PATH without invoking the external command helper" do
      dir = Dir.mktmpdir
      rg = File.join(dir, "rg")
      File.write(rg, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, rg)
      saved_path = ENV.fetch("PATH", nil)
      begin
        ENV["PATH"] = dir
        expect(described_class.rg_executable).to eq(File.realpath(rg))
      ensure
        if saved_path
          ENV["PATH"] = saved_path
        else
          ENV.delete("PATH")
        end
        FileUtils.rm_rf(dir)
      end
    end

    it "returns nil when rg is not on PATH" do
      empty_dir = File.join(Dir.tmpdir, "ollama_agent_no_binaries_#{Process.pid}")
      FileUtils.mkdir_p(empty_dir)
      saved_path = ENV.fetch("PATH", nil)
      begin
        ENV["PATH"] = empty_dir
        expect(described_class.rg_executable).to be_nil
      ensure
        if saved_path
          ENV["PATH"] = saved_path
        else
          ENV.delete("PATH")
        end
        FileUtils.rm_rf(empty_dir)
      end
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "securerandom"

RSpec.describe OllamaAgent::ExternalAgents::Probe do
  before { described_class.clear_cache! }

  describe ".resolve_executable" do
    it "returns nil when binary is unknown and not on PATH" do
      bad_status = instance_double(Process::Status, success?: false)
      allow(Open3).to receive(:capture2).and_call_original
      allow(Open3).to receive(:capture2).with("command", "-v", anything).and_return(["", bad_status])
      agent = { "id" => "x", "binary" => "definitely_missing_binary_xyz_#{SecureRandom.hex(4)}" }
      expect(described_class.resolve_executable(agent)).to be_nil
    end

    it "returns nil when binary name is empty" do
      expect(described_class.resolve_executable({ "id" => "x", "binary" => "" })).to be_nil
    end

    it "falls back to PATH walk when external command helper is missing (ENOENT)" do
      bindir = nil
      previous = ENV.fetch("PATH", nil)
      begin
        bindir = File.join(Dir.tmpdir, "probe_bin_#{SecureRandom.hex(4)}")
        FileUtils.mkdir_p(bindir)
        stub_exe = File.join(bindir, "probe_shim_exe")
        File.write(stub_exe, "#!/bin/sh\necho ok\n")
        File.chmod(0o755, stub_exe)
        allow(Open3).to receive(:capture2).with("command", "-v", "probe_shim_exe").and_raise(Errno::ENOENT)
        ENV["PATH"] = "#{bindir}#{File::PATH_SEPARATOR}#{ENV.fetch("PATH", nil)}"
        agent = { "id" => "shim", "binary" => "probe_shim_exe" }
        expect(described_class.resolve_executable(agent)).to eq(stub_exe)
      ensure
        ENV["PATH"] = previous
        FileUtils.rm_rf(bindir) if bindir && File.directory?(bindir)
      end
    end
  end

  describe ".fetch_status" do
    it "marks unavailable when executable is missing" do
      bad_status = instance_double(Process::Status, success?: false)
      allow(Open3).to receive(:capture2).and_call_original
      allow(Open3).to receive(:capture2).with("command", "-v", anything).and_return(["", bad_status])
      agent = { "id" => "ghost", "binary" => "missing_cli_#{SecureRandom.hex(6)}" }
      row = described_class.fetch_status(agent)
      expect(row["available"]).to be false
      expect(row["error"]).to include("executable not found")
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
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

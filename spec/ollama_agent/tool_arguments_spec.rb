# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OllamaAgent::ToolArguments" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:agent) { OllamaAgent::Agent.new(root: tmpdir, confirm_patches: false) }

  after do
    FileUtils.remove_entry(tmpdir)
  end

  describe "#coerce_tool_arguments" do
    it "deep-merges nested parameters with top-level keys" do
      args = {
        "parameters" => { "meta" => { "a" => 1 } },
        "meta" => { "b" => 2 },
        "path" => "x"
      }
      merged = agent.send(:coerce_tool_arguments, args)
      expect(merged["meta"]).to eq({ "a" => 1, "b" => 2 })
      expect(merged["path"]).to eq("x")
    end
  end
end

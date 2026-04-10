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

    it "does not leave a top-level parameters key in the merged hash" do
      args = { "parameters" => { "path" => "inner.txt" }, "path" => "outer.txt" }
      merged = agent.send(:coerce_tool_arguments, args)
      expect(merged).not_to have_key("parameters")
      expect(merged).not_to have_key(:parameters)
    end

    it "treats nested parameters as higher precedence than duplicate top-level keys" do
      args = { "parameters" => { "path" => "inner.txt" }, "path" => "outer.txt" }
      merged = agent.send(:coerce_tool_arguments, args)
      expect(merged["path"]).to eq("inner.txt")
    end

    context "when parameters are keyed with a symbol" do
      it "merges the nested hash and strips the key" do
        args = { parameters: { "x" => 1 }, "y" => 2 }
        merged = agent.send(:coerce_tool_arguments, args)
        expect(merged).to eq({ "x" => 1, "y" => 2 })
      end
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::SelfImprovement::Analyzer do
  let(:agent) { instance_double(OllamaAgent::Agent, run: nil) }
  let(:analyzer) { described_class.new(agent) }

  describe "#run" do
    it "forwards only the task prompt when preamble is nil" do
      analyzer.run("do the thing")

      expect(agent).to have_received(:run).with("do the thing")
    end

    it "prepends preamble before the task prompt" do
      analyzer.run("do the thing", preamble: "## Extra\n\nnotes")

      expect(agent).to have_received(:run).with("## Extra\n\nnotes\n\ndo the thing")
    end
  end
end

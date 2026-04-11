# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Core::ActionEnvelope do
  describe ".tool_call" do
    subject(:env) { described_class.tool_call(tool: "read_file", args: { path: "lib/foo.rb" }, confidence: 0.9) }

    it "has the correct type" do
      expect(env.type).to eq(:tool_call)
    end

    it "is a tool_call?" do
      expect(env).to be_tool_call
    end

    it "exposes the tool name" do
      expect(env.tool).to eq("read_file")
    end

    it "exposes args" do
      expect(env.args).to eq({ path: "lib/foo.rb" })
    end

    it "stores confidence" do
      expect(env.confidence).to eq(0.9)
    end

    it "generates a unique envelope_id" do
      other = described_class.tool_call(tool: "read_file", args: {})
      expect(env.envelope_id).not_to eq(other.envelope_id)
    end
  end

  describe ".final" do
    subject(:env) { described_class.final(content: "Done!") }

    it { expect(env).to be_final }
    it { expect(env.content).to eq("Done!") }
  end

  describe ".ask_clarification" do
    subject(:env) { described_class.ask_clarification(question: "Which file?") }

    it { expect(env).to be_ask_clarification }
    it { expect(env.question).to eq("Which file?") }
  end

  describe ".error" do
    subject(:env) { described_class.error(message: "Something went wrong") }

    it { expect(env).to be_error }
    it { expect(env.message).to eq("Something went wrong") }
  end

  describe ".handoff" do
    subject(:env) { described_class.handoff(agent: "claude", query: "review this") }

    it { expect(env).to be_handoff }
  end

  describe "predicate exclusivity" do
    let(:tool_env) { described_class.tool_call(tool: "read_file", args: {}) }

    it "is not final" do
      expect(tool_env).not_to be_final
    end

    it "is not error" do
      expect(tool_env).not_to be_error
    end
  end

  describe "#to_h" do
    it "includes type, payload, confidence, and envelope_id" do
      env = described_class.tool_call(tool: "edit_file", args: {}, confidence: 0.8)
      h   = env.to_h
      expect(h[:type]).to eq(:tool_call)
      expect(h[:payload][:tool]).to eq("edit_file")
      expect(h[:confidence]).to eq(0.8)
      expect(h[:envelope_id]).to match(/\Aenv_[0-9a-f]+\z/)
    end
  end

  describe "invalid type" do
    it "raises ArgumentError" do
      expect { described_class.new(type: :unknown, payload: {}) }.to raise_error(ArgumentError)
    end
  end
end

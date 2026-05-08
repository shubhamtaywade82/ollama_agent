# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::KernelBridge do
  let(:hooks) { instance_double(OllamaAgent::Streaming::Hooks, emit: nil) }
  let(:logger) { instance_double(Logger, info: nil) }
  let(:agent) do
    instance_double(
      OllamaAgent::Agent,
      hooks: hooks,
      logger: logger
    )
  end

  before do
    allow(agent).to receive(:send)
  end

  around do |example|
    original_value = ENV.fetch("OLLAMA_AGENT_KERNEL", nil)
    example.run
    ENV["OLLAMA_AGENT_KERNEL"] = original_value
  end

  describe "#append_tool_results" do
    let(:messages) { [{ role: "user", content: "hi" }] }
    let(:tool_calls) { [{ "name" => "read_file" }] }

    context "when kernel flag is disabled" do
      it "uses legacy append behavior without emitting kernel event" do
        ENV["OLLAMA_AGENT_KERNEL"] = "false"
        bridge = described_class.new(agent)

        bridge.append_tool_results(messages: messages, tool_calls: tool_calls)

        expect(agent).to have_received(:send).with(:append_tool_results, messages, tool_calls)
        expect(hooks).not_to have_received(:emit)
      end
    end

    context "when kernel flag is enabled" do
      it "emits runtime kernel event and delegates append through legacy flow" do
        ENV["OLLAMA_AGENT_KERNEL"] = "true"
        bridge = described_class.new(agent)

        bridge.append_tool_results(messages: messages, tool_calls: tool_calls)

        expect(hooks).to have_received(:emit).with(
          :on_tool_runtime_kernel,
          { enabled: true, tool_call_count: 1 }
        )
        expect(agent).to have_received(:send).with(:append_tool_results, messages, tool_calls)
      end
    end
  end
end

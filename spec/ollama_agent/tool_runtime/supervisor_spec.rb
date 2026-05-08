# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::ToolRuntime::Supervisor do
  let(:schema) do
    {
      "type" => "object",
      "required" => ["steps"],
      "properties" => {
        "steps" => { "type" => "array" }
      }
    }
  end

  # rubocop:disable RSpec/VerifiedDoubles
  let(:llm_client) { double("llm_client") }
  # rubocop:enable RSpec/VerifiedDoubles
  let(:planner) { OllamaAgent::LLM::Planner.new(llm_client: llm_client, schema: schema) }
  let(:registry) { OllamaAgent::ToolRuntime::ToolRegistry.new }

  it "orchestrates planner output through phase-matched tools" do
    allow(llm_client).to receive(:chat).and_return(
      '{"steps":[{"tool":"double","args":{"n":3}}]}'
    )
    registry.register(
      name: "double",
      callable: ->(n:) { n * 2 },
      phases: %i[planning]
    )
    sup = described_class.new(planner: planner, tool_registry: registry, max_local_attempts: 3)
    out = sup.orchestrate(prompt: "run", context: [], phase: :planning)
    expect(out[:escalated]).to be(false)
    expect(out[:result][:tool_results]).to eq([{ tool: "double", result: 6 }])
  end

  it "escalates when the planner exhausts retries" do
    stub_planner = instance_double(OllamaAgent::LLM::Planner)
    allow(stub_planner).to receive(:plan).and_return(:invalid_after_retries)
    called = []
    sup = described_class.new(
      planner: stub_planner,
      tool_registry: registry,
      escalation_callback: proc { called << :cb },
      max_local_attempts: 3
    )
    out = sup.orchestrate(prompt: "run", context: [], phase: :planning)
    expect(out).to eq({ result: :escalated, escalated: true })
    expect(called).to eq([:cb])
  end

  it "escalates when max_local_attempts yield no tool progress" do
    allow(llm_client).to receive(:chat).and_return('{"steps":[]}')
    sup = described_class.new(planner: planner, tool_registry: registry, max_local_attempts: 2)
    out = sup.orchestrate(prompt: "run", context: [], phase: :planning)
    expect(out[:escalated]).to be(true)
    expect(llm_client).to have_received(:chat).exactly(2).times
  end

  it "raises ToolPhaseError when a tool is not available in the current phase" do
    allow(llm_client).to receive(:chat).and_return(
      '{"steps":[{"tool":"mut","args":{}}]}'
    )
    registry.register(name: "mut", callable: ->(**) { 1 }, phases: %i[mutation])
    sup = described_class.new(planner: planner, tool_registry: registry, max_local_attempts: 3)
    expect do
      sup.orchestrate(prompt: "run", context: [], phase: :planning)
    end.to raise_error(OllamaAgent::ToolRuntime::ToolPhaseError)
  end
end

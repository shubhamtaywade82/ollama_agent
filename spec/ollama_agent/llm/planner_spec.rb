# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::LLM::Planner do
  let(:schema) do
    {
      "type" => "object",
      "required" => ["steps"],
      "properties" => {
        "steps" => { "type" => "array" },
        "note" => { "type" => "string" }
      }
    }
  end

  # rubocop:disable RSpec/VerifiedDoubles -- duck-typed LLM client has no concrete class here
  let(:llm_client) { double("llm_client") }
  # rubocop:enable RSpec/VerifiedDoubles

  def planner_with(client, **opts)
    described_class.new(llm_client: client, schema: schema, **opts)
  end

  it "returns a validated plan on a happy path" do
    allow(llm_client).to receive(:chat).and_return('{"steps":[],"note":"ok"}')
    p = planner_with(llm_client)
    out = p.plan(prompt: "go", context: [], phase: :planning)
    expect(out).to eq({ plan: { "steps" => [], "note" => "ok" } })
  end

  it "strips redacted_thinking before parsing JSON" do
    raw = "<think>secret</think>\n{\"steps\":[]}"
    allow(llm_client).to receive(:chat).and_return(raw)
    p = planner_with(llm_client)
    out = p.plan(prompt: "go", context: [], phase: :planning)
    expect(out).to eq({ plan: { "steps" => [] } })
  end

  it "retries when JSON is malformed then succeeds" do
    allow(llm_client).to receive(:chat)
      .and_return("preamble { broken", '{"steps":[]}')
    p = planner_with(llm_client, max_retries: 3)
    out = p.plan(prompt: "go", context: [], phase: :planning)
    expect(out).to eq({ plan: { "steps" => [] } })
    expect(llm_client).to have_received(:chat).twice
  end

  it "retries when schema types mismatch then succeeds" do
    allow(llm_client).to receive(:chat)
      .and_return('{"steps":"nope"}', '{"steps":[]}')
    p = planner_with(llm_client, max_retries: 3)
    out = p.plan(prompt: "go", context: [], phase: :planning)
    expect(out).to eq({ plan: { "steps" => [] } })
    expect(llm_client).to have_received(:chat).twice
  end

  it "returns :invalid_after_retries when validation never succeeds" do
    allow(llm_client).to receive(:chat).and_return("not json")
    p = planner_with(llm_client, max_retries: 2)
    out = p.plan(prompt: "go", context: [], phase: :planning)
    expect(out).to eq(:invalid_after_retries)
    expect(llm_client).to have_received(:chat).exactly(3).times
  end

  it "returns :budget_exceeded when prompt+context exceed max_context_tokens" do
    # rubocop:disable RSpec/VerifiedDoubles
    counter = double("token_counter")
    # rubocop:enable RSpec/VerifiedDoubles
    allow(counter).to receive(:count).with(text: "").and_return(0)
    allow(counter).to receive(:count).with(text: "go").and_return(100)
    allow(llm_client).to receive(:chat)
    p = planner_with(llm_client, max_context_tokens: 50, token_counter: counter)
    out = p.plan(prompt: "go", context: [], phase: :planning)
    expect(out).to eq(:budget_exceeded)
    expect(llm_client).not_to have_received(:chat)
  end

  it "extracts the first balanced object when extra braces appear in strings" do
    allow(llm_client).to receive(:chat).and_return(
      '{"steps":[{"tool":"x","args":{"q":"}"}}]}'
    )
    nested_schema = {
      "type" => "object",
      "required" => ["steps"],
      "properties" => {
        "steps" => { "type" => "array" }
      }
    }
    p = described_class.new(llm_client: llm_client, schema: nested_schema)
    out = p.plan(prompt: "go", context: [], phase: :planning)
    expect(out[:plan]["steps"].size).to eq(1)
  end
end

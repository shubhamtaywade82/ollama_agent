# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent, ".tools_for" do
  it "includes orchestrator tools when orchestrator is true" do
    t = described_class.tools_for(read_only: false, orchestrator: true)
    names = t.map { |x| x.dig(:function, :name) }
    expect(names).to include("list_external_agents", "delegate_to_agent")
  end

  it "omits delegate when read_only and orchestrator" do
    t = described_class.tools_for(read_only: true, orchestrator: true)
    names = t.map { |x| x.dig(:function, :name) }
    expect(names).to include("list_external_agents")
    expect(names).not_to include("delegate_to_agent")
  end

  it "matches legacy TOOLS count when orchestrator is false" do
    t = described_class.tools_for(read_only: false, orchestrator: false)
    expect(t.size).to eq(described_class::TOOLS.size)
  end
end

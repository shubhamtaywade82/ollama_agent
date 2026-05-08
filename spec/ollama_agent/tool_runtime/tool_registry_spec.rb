# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::ToolRuntime::ToolRegistry do
  let(:registry) { described_class.new }

  it "registers tools and filters available_in by phase" do
    registry.register(name: "alpha", callable: -> { :a }, phases: %i[planning])
    registry.register(name: "beta", callable: -> { :b }, phases: %i[mutation])

    planning = registry.available_in(phase: :planning)
    expect(planning.map { |t| t[:name] }).to eq(["alpha"])

    mutation = registry.available_in(phase: :mutation)
    expect(mutation.map { |t| t[:name] }).to eq(["beta"])
  end

  it "invokes a callable when the phase matches" do
    registry.register(name: "echo", callable: ->(x:) { x }, phases: %i[verification])
    expect(registry.invoke(name: "echo", phase: :verification, x: 7)).to eq(7)
  end

  it "returns :tool_not_available_in_phase when the tool exists but not in that phase" do
    registry.register(name: "mut", callable: -> { 1 }, phases: %i[mutation])
    expect(registry.invoke(name: "mut", phase: :planning)).to eq(:tool_not_available_in_phase)
  end

  it "rejects duplicate tool names" do
    registry.register(name: "one", callable: -> { 1 }, phases: %i[planning])
    expect do
      registry.register(name: "one", callable: -> { 2 }, phases: %i[planning])
    end.to raise_error(ArgumentError, /duplicate/)
  end
end

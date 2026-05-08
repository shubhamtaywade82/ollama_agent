# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Synthesis::EventSchemaRegistry do
  let(:registry) { described_class.new }

  before do
    registry.register(
      event_name: "order.created",
      schema: {
        required: %w[id],
        properties: {
          "id" => { "type" => "integer" },
          "label" => { "type" => "string" }
        }
      }
    )
  end

  it "accepts a valid payload" do
    result = registry.validate(event_name: "order.created", payload: { "id" => 1, "label" => "a" })
    expect(result[:valid]).to be(true)
    expect(result[:errors]).to be_empty
  end

  it "reports a missing required key" do
    result = registry.validate(event_name: "order.created", payload: { "label" => "x" })
    expect(result[:valid]).to be(false)
    expect(result[:errors].join).to include("id")
  end

  it "reports a wrong property type" do
    result = registry.validate(event_name: "order.created", payload: { "id" => "nope" })
    expect(result[:valid]).to be(false)
    expect(result[:errors].join).to include("id")
  end

  it "raises UnknownEvent for unregistered names" do
    expect do
      registry.validate(event_name: "missing.event", payload: {})
    end.to raise_error(OllamaAgent::Synthesis::UnknownEvent)
  end
end

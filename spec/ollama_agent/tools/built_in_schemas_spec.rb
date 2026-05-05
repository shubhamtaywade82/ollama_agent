# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::BuiltInSchemas do
  after { described_class.reset_registrations! }

  describe ".register" do
    it "appends a schema in read-write mode" do
      schema = { type: "function", function: { name: "custom_echo", description: "x", parameters: { type: "object" } } }
      described_class.register(schema, read_only: false, read_write_too: true)
      names = described_class.tools_for(read_only: false, orchestrator: false, custom_schemas: []).map { |t| t.dig(:function, :name) }
      expect(names).to include("custom_echo")
    end
  end
end

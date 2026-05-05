# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Skills::Base do
  let(:fake_llm_class) { Class.new { def generate(_prompt); end } }
  let(:llm) { instance_double(fake_llm_class, generate: response) }

  let(:skill_class) { TestEchoSkill }

  let(:test_schema) do
    {
      type: "object",
      required: %w[message],
      properties: { message: { type: "string", minLength: 1 } }
    }.freeze
  end

  before do
    klass = Class.new(described_class) do
      register_as :test_echo

      def prompt(input)
        "echo: #{input[:value]}"
      end
    end
    stub_const("TestEchoSkill", klass)
    stub_const("TestEchoSkill::SCHEMA", test_schema)
  end

  context "with valid JSON output that matches the schema" do
    let(:response) { '{"message": "hello"}' }

    it "returns the parsed payload" do
      expect(skill_class.new(llm: llm).call(value: "x")).to eq(message: "hello")
    end

    it "passes the rendered prompt to the LLM" do
      skill_class.new(llm: llm).call(value: "x")
      expect(llm).to have_received(:generate).with("echo: x")
    end
  end

  context "with output that violates the schema" do
    let(:response) { '{"wrong_key": 1}' }

    it "raises ContractError" do
      expect { skill_class.new(llm: llm).call(value: "x") }
        .to raise_error(described_class::ContractError, /test_echo contract violation/)
    end
  end

  context "with non-Hash input" do
    let(:response) { "{}" }

    it "raises ArgumentError before calling the LLM" do
      expect { skill_class.new(llm: llm).call("not a hash") }
        .to raise_error(ArgumentError, /must be a Hash/)
      expect(llm).not_to have_received(:generate)
    end
  end

  context "without register_as" do
    it "raises NotImplementedError when skill_id is requested" do
      anonymous = Class.new(described_class)
      expect { anonymous.skill_id }.to raise_error(NotImplementedError, /register_as/)
    end
  end
end

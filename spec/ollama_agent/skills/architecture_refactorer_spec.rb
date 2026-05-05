# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Skills::ArchitectureRefactorer do
  let(:fake_llm_class) { Class.new { def generate(_prompt); end } }
  let(:llm) { instance_double(fake_llm_class, generate: response) }

  context "with a well-formed contract response" do
    let(:response) do
      <<~JSON
        Sure, here's the plan:
        ```json
        {
          "folder_structure": ["lib/orders.rb", "lib/orders/manager.rb"],
          "architecture_notes": "Split Orders::Manager into command + query objects.",
          "refactored_code": "module Orders; class Manager; end; end"
        }
        ```
      JSON
    end

    it "returns the parsed payload with all required keys" do
      result = described_class.new(llm: llm).call(code: "class Foo; end")

      expect(result).to include(
        :folder_structure, :architecture_notes, :refactored_code
      )
      expect(result[:folder_structure]).to be_an(Array)
    end
  end

  context "without :code in the input" do
    let(:response) { "{}" }

    it "raises ArgumentError before calling the LLM" do
      expect { described_class.new(llm: llm).call({}) }
        .to raise_error(ArgumentError, /missing :code/)
    end
  end

  context "with response missing required keys" do
    let(:response) { '{"refactored_code": "x"}' }

    it "raises ContractError" do
      expect { described_class.new(llm: llm).call(code: "class Foo; end") }
        .to raise_error(OllamaAgent::Skills::Base::ContractError, /architecture_refactor/)
    end
  end
end

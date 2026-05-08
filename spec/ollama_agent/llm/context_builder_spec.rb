# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::LLM::ContextBuilder do
  let(:token_counter) do
    Class.new do
      def self.count(text:)
        text.to_s.length
      end
    end
  end

  it "honors per-section caps using exact token math (length counter)" do
    builder = described_class.new(max_tokens: 100, token_counter: token_counter)
    msgs = builder.build(system: "a" * 10, history: "b" * 30, focus: "c" * 50)
    b30 = "b" * 30
    c50 = "c" * 50
    joined_user = "#{b30}\n\n#{c50}"
    expect(msgs).to eq(
      [
        { "role" => "system", "content" => "a" * 10 },
        { "role" => "user", "content" => joined_user }
      ]
    )
  end

  it "raises BudgetExceeded when a section overflows its fraction of max_tokens" do
    builder = described_class.new(max_tokens: 100, token_counter: token_counter)
    expect do
      builder.build(system: "a" * 11, history: "", focus: "")
    end.to raise_error(OllamaAgent::BudgetExceeded, /system tokens/)
  end

  it "raises BudgetExceeded on history overflow even when system and focus fit" do
    builder = described_class.new(max_tokens: 100, token_counter: token_counter)
    expect do
      builder.build(system: "a" * 10, history: "b" * 31, focus: "")
    end.to raise_error(OllamaAgent::BudgetExceeded, /history tokens/)
  end
end

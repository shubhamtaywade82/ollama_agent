# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Core::Budget do
  subject(:budget) { described_class.new(max_steps: 5, max_tokens: 1000, max_cost_usd: 0.10) }

  describe "#record_step!" do
    it "increments step count" do
      budget.record_step!
      expect(budget.steps).to eq(1)
    end

    it "accumulates tokens" do
      budget.record_step!(tokens: 300)
      budget.record_step!(tokens: 200)
      expect(budget.tokens_used).to eq(500)
    end

    it "accumulates cost" do
      budget.record_step!(cost_usd: 0.02)
      expect(budget.cost_usd).to be_within(0.0001).of(0.02)
    end
  end

  describe "#exceeded?" do
    it "is false below limits" do
      4.times { budget.record_step! }
      expect(budget).not_to be_exceeded
    end

    it "is true when steps hit limit" do
      5.times { budget.record_step! }
      expect(budget).to be_steps_exceeded
      expect(budget).to be_exceeded
    end

    it "is true when tokens hit limit" do
      budget.record_step!(tokens: 1001)
      expect(budget).to be_tokens_exceeded
    end

    it "is true when cost hits limit" do
      budget.record_step!(cost_usd: 0.11)
      expect(budget).to be_cost_exceeded
    end
  end

  describe "#exceeded_reason" do
    it "returns nil when not exceeded" do
      expect(budget.exceeded_reason).to be_nil
    end

    it "returns step reason" do
      5.times { budget.record_step! }
      expect(budget.exceeded_reason).to include("step limit")
    end

    it "returns token reason" do
      budget.record_step!(tokens: 5000)
      expect(budget.exceeded_reason).to include("token limit")
    end
  end

  describe "#remaining_steps" do
    it "counts down correctly" do
      2.times { budget.record_step! }
      expect(budget.remaining_steps).to eq(3)
    end

    it "never goes negative" do
      10.times { budget.record_step! }
      expect(budget.remaining_steps).to eq(0)
    end
  end

  describe "#reset!" do
    it "clears all counters" do
      5.times { budget.record_step!(tokens: 100, cost_usd: 0.01) }
      budget.reset!
      expect(budget.steps).to eq(0)
      expect(budget.tokens_used).to eq(0)
      expect(budget.cost_usd).to eq(0.0)
    end
  end

  describe "#to_h" do
    it "includes all fields" do
      budget.record_step!(tokens: 50)
      h = budget.to_h
      expect(h).to include(:steps, :max_steps, :tokens_used, :max_tokens, :cost_usd, :max_cost_usd)
    end
  end
end

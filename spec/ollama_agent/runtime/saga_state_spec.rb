# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::SagaState do
  describe ".can_transition?" do
    it "matches the ALLOWED matrix for every ordered pair in STATES" do
      described_class::STATES.each do |from|
        described_class::STATES.each do |to|
          expected = described_class::ALLOWED.fetch(from, []).include?(to)
          expect(described_class.can_transition?(from, to)).to eq(expected)
        end
      end
    end

    it "accepts symbol state names the same as strings" do
      expect(described_class.can_transition?(:reserved, :locked)).to be(true)
      expect(described_class.can_transition?(:committed, :compensated)).to be(false)
    end
  end

  describe ".terminal?" do
    it "is true only for committed and compensated" do
      described_class::STATES.each do |state|
        expected = described_class::TERMINAL.include?(state)
        expect(described_class.terminal?(state)).to eq(expected)
      end
    end
  end
end

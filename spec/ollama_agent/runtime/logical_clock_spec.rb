# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::LogicalClock do
  describe "#next_stamp" do
    it "returns deterministic monotonic stamps without wall clock" do
      clock = described_class.new(epoch: 1)

      expect(clock.next_stamp).to eq("1:1")
      expect(clock.next_stamp).to eq("1:2")
    end
  end
end

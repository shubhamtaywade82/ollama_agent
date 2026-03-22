# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::SelfImprovement::Modes do
  describe ".normalize" do
    it "maps numeric and name aliases" do
      expect(described_class.normalize("1")).to eq("analysis")
      expect(described_class.normalize("2")).to eq("interactive")
      expect(described_class.normalize("3")).to eq("automated")
      expect(described_class.normalize("fix")).to eq("interactive")
      expect(described_class.normalize("sandbox")).to eq("automated")
    end
  end

  describe ".valid?" do
    it "accepts canonical modes only" do
      expect(described_class.valid?("analysis")).to be(true)
      expect(described_class.valid?("bogus")).to be(false)
    end
  end
end

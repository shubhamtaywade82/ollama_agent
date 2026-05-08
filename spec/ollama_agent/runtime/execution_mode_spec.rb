# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::ExecutionMode do
  describe ".valid?" do
    it "returns true for supported execution modes" do
      expect(described_class.valid?("normal")).to be(true)
      expect(described_class.valid?("replay")).to be(true)
      expect(described_class.valid?("validation")).to be(true)
      expect(described_class.valid?("dry_run")).to be(true)
    end

    it "returns false for unsupported execution modes" do
      expect(described_class.valid?("unknown")).to be(false)
    end
  end
end

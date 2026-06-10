# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::TieredAgent::HardwareProfile do
  describe ".for_vram" do
    it "returns :minimal for nil (no GPU)" do
      expect(described_class.for_vram(nil).name).to eq(:minimal)
    end

    it "returns :minimal for 0 GB" do
      expect(described_class.for_vram(0).name).to eq(:minimal)
    end

    it "returns :minimal for 8 GB" do
      expect(described_class.for_vram(8).name).to eq(:minimal)
    end

    it "returns :standard for 10 GB" do
      expect(described_class.for_vram(10).name).to eq(:standard)
    end

    it "returns :standard for 12 GB" do
      expect(described_class.for_vram(12).name).to eq(:standard)
    end

    it "returns :performance for 14 GB" do
      expect(described_class.for_vram(14).name).to eq(:performance)
    end

    it "returns :performance for 16 GB" do
      expect(described_class.for_vram(16).name).to eq(:performance)
    end

    it "returns :high for 22 GB" do
      expect(described_class.for_vram(22).name).to eq(:high)
    end

    it "returns :high for 24 GB" do
      expect(described_class.for_vram(24).name).to eq(:high)
    end

    it "returns :ultra for 30 GB" do
      expect(described_class.for_vram(30).name).to eq(:ultra)
    end

    it "returns :ultra for 32 GB" do
      expect(described_class.for_vram(32).name).to eq(:ultra)
    end

    it "returns :maximum for 44 GB" do
      expect(described_class.for_vram(44).name).to eq(:maximum)
    end

    it "returns :maximum for 80 GB (H100)" do
      expect(described_class.for_vram(80).name).to eq(:maximum)
    end
  end

  describe ".find" do
    it "finds a profile by symbol" do
      p = described_class.find(:performance)
      expect(p.name).to eq(:performance)
    end

    it "finds a profile by string" do
      p = described_class.find("ultra")
      expect(p.name).to eq(:ultra)
    end

    it "returns nil for unknown names" do
      expect(described_class.find(:nonexistent)).to be_nil
    end
  end

  describe ".all_names" do
    it "returns all profile names in ascending VRAM order" do
      expect(described_class.all_names).to eq(
        %i[minimal standard performance high ultra maximum]
      )
    end
  end

  describe "profile content sanity checks" do
    it "every profile has a non-empty model_small" do
      described_class::PROFILES.each do |p|
        expect(p.model_small).not_to be_empty, "#{p.name} missing model_small"
      end
    end

    it "every profile has a non-empty model_medium" do
      described_class::PROFILES.each do |p|
        expect(p.model_medium).not_to be_empty, "#{p.name} missing model_medium"
      end
    end

    it "every profile has a non-empty model_large" do
      described_class::PROFILES.each do |p|
        expect(p.model_large).not_to be_empty, "#{p.name} missing model_large"
      end
    end

    it "context windows grow with VRAM tier" do
      ctx_values = described_class::PROFILES.map(&:num_ctx)
      expect(ctx_values).to eq(ctx_values.sort), "num_ctx should be non-decreasing across profiles"
    end

    it "minimum_vram_gb thresholds are non-decreasing" do
      thresholds = described_class::PROFILES.map(&:minimum_vram_gb)
      expect(thresholds).to eq(thresholds.sort)
    end

    it "the first profile has minimum_vram_gb of 0 (catch-all)" do
      expect(described_class::PROFILES.first.minimum_vram_gb).to eq(0)
    end
  end

  describe ".summary_table" do
    it "includes all profile names" do
      table = described_class.summary_table
      described_class.all_names.each do |name|
        expect(table).to include(name.to_s)
      end
    end
  end

  describe "Profile struct" do
    subject(:profile) { described_class.find(:performance) }

    it "exposes label" do
      expect(profile.label).to include("16 GB")
    end

    it "exposes description" do
      expect(profile.description).not_to be_empty
    end

    it "exposes keep_alive as a string" do
      expect(profile.keep_alive).to match(/\d+s/)
    end
  end
end

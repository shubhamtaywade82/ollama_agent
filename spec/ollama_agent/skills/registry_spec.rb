# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Skills::Registry do
  subject(:registry) { described_class.new }

  describe "#register and #fetch" do
    it "registers and retrieves a skill class by symbol" do
      klass = Class.new
      registry.register(:demo, klass)
      expect(registry.fetch(:demo)).to eq(klass)
    end

    it "treats string names as symbols" do
      klass = Class.new
      registry.register("demo", klass)
      expect(registry.fetch("demo")).to eq(klass)
    end
  end

  describe "#fetch with unknown name" do
    it "raises UnknownSkill listing known names" do
      registry.register(:known, Class.new)
      expect { registry.fetch(:missing) }
        .to raise_error(described_class::UnknownSkill, /missing.*Known: known/)
    end
  end

  describe ".registry singleton" do
    it "exposes built-in skills registered via register_as" do
      expect(OllamaAgent::Skills.registry.names).to include(
        :architecture_refactor, :performance_optimizer, :debug_engineer, :feature_builder
      )
    end
  end
end

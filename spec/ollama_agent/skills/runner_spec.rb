# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Skills::Runner do
  # Lightweight test doubles that mirror Skills::Base#new(llm:) and #call.
  # They record the inputs they received so we can assert pipeline plumbing.
  def make_skill_class(payload)
    klass = recording_skill_class
    klass.define_singleton_method(:payload) { payload }
    klass
  end

  def recording_skill_class
    klass = Class.new(SkillBaseDouble)
    klass.define_singleton_method(:observed) { @observed ||= [] }
    klass
  end

  before do
    stub_const(
      "SkillBaseDouble",
      Class.new do
        def initialize(llm: nil)
          @llm = llm
        end

        def call(input)
          self.class.observed << input
          self.class.payload
        end
      end
    )
  end

  let(:first_skill_class)  { make_skill_class(added: 1) }
  let(:second_skill_class) { make_skill_class(added: 2) }

  describe "#call" do
    it "merges each skill's output into the accumulator" do
      result = described_class.new([first_skill_class, second_skill_class]).call(seed: "x")

      expect(result).to eq(seed: "x", added: 2)
    end

    it "passes accumulated context to each skill in order" do
      described_class.new([first_skill_class, second_skill_class]).call(seed: "x")

      expect(first_skill_class.observed).to eq([{ seed: "x" }])
      expect(second_skill_class.observed).to eq([{ seed: "x", added: 1 }])
    end

    it "resolves symbol step names through the registry" do
      OllamaAgent::Skills.registry.register(:fake_step, first_skill_class)
      result = described_class.new([:fake_step]).call(seed: "y")

      expect(result).to eq(seed: "y", added: 1)
    end
  end

  describe ".new with empty steps" do
    it "raises ArgumentError" do
      expect { described_class.new([]) }.to raise_error(ArgumentError, /at least one skill/)
    end
  end
end

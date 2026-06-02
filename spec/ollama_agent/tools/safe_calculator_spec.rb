# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::SafeCalculator do
  let(:tool) { described_class.new }

  def calc(expression)
    tool.call({ "expression" => expression })
  end

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("calculate")
    end

    it "is low risk and requires no approval" do
      expect(tool.risk_level).to eq(:low)
      expect(tool.requires_approval).to be(false)
    end
  end

  describe "#call — basic arithmetic" do
    it "adds integers" do
      expect(calc("2 + 3")).to eq("5.0")
    end

    it "subtracts integers" do
      expect(calc("10 - 4")).to eq("6.0")
    end

    it "multiplies integers" do
      expect(calc("3 * 4")).to eq("12.0")
    end

    it "divides integers" do
      expect(calc("10 / 4")).to eq("2.5")
    end

    it "handles exponentiation" do
      expect(calc("2 ** 10")).to eq("1024.0")
    end

    it "handles float literals" do
      expect(calc("1.5 + 2.5")).to eq("4.0")
    end
  end

  describe "#call — operator precedence" do
    it "respects * over +" do
      expect(calc("2 + 3 * 4")).to eq("14.0")
    end

    it "respects ** over *" do
      expect(calc("2 * 3 ** 2")).to eq("18.0")
    end
  end

  describe "#call — parentheses" do
    it "overrides precedence with parens" do
      expect(calc("(2 + 3) * 4")).to eq("20.0")
    end

    it "handles nested parentheses" do
      expect(calc("((2 + 3) * (4 - 1))")).to eq("15.0")
    end
  end

  describe "#call — right-associativity of **" do
    it "evaluates 2 ** 3 ** 2 as 2 ** (3 ** 2) = 512" do
      expect(calc("2 ** 3 ** 2")).to eq("512.0")
    end
  end

  describe "#call — unary operators" do
    it "handles unary minus" do
      expect(calc("-5 + 10")).to eq("5.0")
    end

    it "handles unary plus" do
      expect(calc("+5")).to eq("5.0")
    end

    it "handles unary on sub-expression" do
      expect(calc("-(3 + 2)")).to eq("-5.0")
    end
  end

  describe "#call — real-world use cases" do
    it "computes a sum of several numbers" do
      expect(calc("412 + 1834 + 10786 + 88 + 2210")).to eq("15330.0")
    end

    it "converts bytes to kilobytes" do
      expect(calc("15330 / 1024")).to match(/14\.9/)
    end
  end

  describe "#call — error handling" do
    it "returns an error for an empty expression" do
      expect(calc("")).to match(/Error/)
    end

    it "returns an error for invalid characters" do
      expect(calc("2 + x")).to match(/Error/)
    end

    it "returns an error for mismatched opening paren" do
      expect(calc("(2 + 3")).to match(/Error/)
    end

    it "returns an error for mismatched closing paren" do
      expect(calc("2 + 3)")).to match(/Error/)
    end

    it "returns non-finite message for division by zero" do
      result = calc("1 / 0")
      expect(result).to match(/non-finite|Infinity/)
    end
  end
end

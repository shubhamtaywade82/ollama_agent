# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::PatchRisk do
  describe ".assess" do
    let(:tiny_diff) do
      <<~DIFF
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -a
        +b
      DIFF
    end

    it "auto-approves small markdown edits" do
      expect(described_class.assess("README.md", tiny_diff)).to eq(:auto_approve)
    end

    it "requires confirmation for Gemfile paths" do
      expect(described_class.assess("Gemfile", tiny_diff)).to eq(:require_confirmation)
    end

    it "requires confirmation when the diff is large" do
      many = (+"".dup) << tiny_diff
      many << ("+x\n" * 100)
      expect(described_class.assess("README.md", many)).to eq(:require_confirmation)
    end

    it "requires confirmation for forbidden content" do
      bad = "#{tiny_diff}\n+eval(\"pwn\")\n"
      expect(described_class.assess("README.md", bad)).to eq(:require_confirmation)
    end
  end
end

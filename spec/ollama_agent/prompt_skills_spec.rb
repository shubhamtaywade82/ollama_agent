# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::PromptSkills do
  describe ".strip_frontmatter" do
    it "returns body after closing frontmatter delimiter" do
      text = <<~MD
        ---
        name: x
        ---
        # Hello

        Body.
      MD
      expect(described_class.strip_frontmatter(text)).to eq("# Hello\n\nBody.\n")
    end

    it "returns original text when there is no closing ---" do
      text = "---\nfoo: bar\n"
      expect(described_class.strip_frontmatter(text)).to eq(text)
    end
  end

  describe ".compose" do
    it "concatenates base and bundled when enabled" do
      base = "BASE"
      allow(described_class).to receive(:bundled_text).and_return("BUNDLED")
      result = described_class.compose(base: base, skills_enabled: true, external_skills_enabled: false)
      expect(result).to include("BASE")
      expect(result).to include("BUNDLED")
    end

    it "omits bundled when skills_enabled is false" do
      base = "ONLY"
      result = described_class.compose(base: base, skills_enabled: false, external_skills_enabled: false)
      expect(result).to eq("ONLY")
    end
  end

  describe ".filter_ids / manifest" do
    let(:entries) do
      [
        { "id" => "a", "file" => "a.md" },
        { "id" => "b", "file" => "b.md" },
        { "id" => "c", "file" => "c.md" }
      ]
    end

    it "orders by INCLUDE list" do
      filtered = described_class.filter_ids(entries, skills_include: "c,a", skills_exclude: nil)
      expect(filtered.map { |e| e["id"] }).to eq(%w[c a])
    end

    it "applies EXCLUDE after manifest order" do
      filtered = described_class.filter_ids(entries, skills_include: nil, skills_exclude: "b")
      expect(filtered.map { |e| e["id"] }).to eq(%w[a c])
    end
  end

  describe "external paths" do
    let(:fixture_file) { File.expand_path("../fixtures/prompt_skills/extra.md", __dir__) }
    let(:fixture_dir) { File.expand_path("../fixtures/prompt_skills/dir", __dir__) }

    it "reads a file path" do
      merged = described_class.merge_skill_paths([fixture_file])
      expect(merged).to include(fixture_file)
      text = described_class.external_text(skill_paths: [fixture_file], external_skills_enabled: true)
      expect(text).to include("fixture-extra-body")
    end

    it "reads all *.md in a directory in sorted order" do
      text = described_class.external_text(skill_paths: [fixture_dir], external_skills_enabled: true)
      expect(text).to include("alpha-fixture")
      expect(text).to include("beta-fixture")
    end

    it "returns empty when external_skills_enabled is false" do
      text = described_class.external_text(
        skill_paths: [fixture_file],
        external_skills_enabled: false
      )
      expect(text).to eq("")
    end
  end
end

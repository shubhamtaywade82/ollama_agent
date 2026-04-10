# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::SelfImprovement::RubyMasteryContext do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  describe ".markdown_section" do
    it "returns nil when the gem cannot be loaded" do
      allow(described_class).to receive_messages(load_gem: false)

      expect(described_class.markdown_section(dir)).to be_nil
    end

    it "returns nil for a blank path" do
      allow(described_class).to receive_messages(load_gem: true)

      expect(described_class.markdown_section("   ")).to be_nil
    end

    it "wraps markdown from RubyMastery.report" do
      allow(described_class).to receive_messages(load_gem: true)
      stub_const("RubyMastery", Module.new)
      allow(RubyMastery).to receive(:report).with(dir, format: :markdown).and_return("# Issues\n\n- one")

      out = described_class.markdown_section(dir)

      expect(out).to include("Static analysis (ruby_mastery)")
      expect(out).to include("# Issues")
      expect(out).to include("- one")
    end

    it "truncates when the report exceeds the character limit" do
      allow(described_class).to receive_messages(load_gem: true)
      stub_const("RubyMastery", Module.new)
      long = "a" * 100
      allow(RubyMastery).to receive(:report).and_return(long)

      previous = ENV.fetch("OLLAMA_AGENT_RUBY_MASTERY_MAX_CHARS", nil)
      ENV["OLLAMA_AGENT_RUBY_MASTERY_MAX_CHARS"] = "20"
      begin
        out = described_class.markdown_section(dir)

        expect(out).to include("(truncated")
        expect(out).not_to include("a" * 50)
      ensure
        if previous
          ENV["OLLAMA_AGENT_RUBY_MASTERY_MAX_CHARS"] = previous
        else
          ENV.delete("OLLAMA_AGENT_RUBY_MASTERY_MAX_CHARS")
        end
      end
    end
  end
end

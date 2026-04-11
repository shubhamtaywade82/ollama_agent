# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Indexing::DiffSummarizer do
  let(:diff) do
    <<~DIFF
      diff --git a/lib/foo.rb b/lib/foo.rb
      --- a/lib/foo.rb
      +++ b/lib/foo.rb
      @@ -1,5 +1,6 @@
      +# Added comment
       class Foo
      -  def old_method
      +  def new_method
         true
       end
       end
      diff --git a/lib/bar.rb b/lib/bar.rb
      new file mode 100644
      --- /dev/null
      +++ b/lib/bar.rb
      @@ -0,0 +1,3 @@
      +class Bar
      +end
    DIFF
  end

  describe ".parse" do
    subject(:parsed) { described_class.parse(diff) }

    it "returns two file diffs" do
      expect(parsed.size).to eq(2)
    end

    it "detects the new file" do
      bar = parsed.find { |f| f.path.include?("bar.rb") }
      expect(bar.is_new).to be(true)
    end

    it "counts additions correctly for lib/foo.rb" do
      foo = parsed.find { |f| f.path.include?("foo.rb") }
      expect(foo.additions).to be >= 1
    end

    it "counts deletions correctly for lib/foo.rb" do
      foo = parsed.find { |f| f.path.include?("foo.rb") }
      expect(foo.deletions).to be >= 1
    end
  end

  describe ".summarize" do
    it "includes file count and change totals" do
      summary = described_class.summarize(diff)
      expect(summary).to match(/\d+ file/)
      expect(summary).to include("lib/foo.rb")
    end

    it "marks new files" do
      summary = described_class.summarize(diff)
      expect(summary).to include("[new]")
    end
  end

  describe "empty diff" do
    it "returns empty string for summarize" do
      expect(described_class.summarize("")).to eq("Empty diff")
    end

    it "returns empty array for parse" do
      expect(described_class.parse("")).to eq([])
    end
  end
end

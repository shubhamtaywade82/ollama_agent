# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::State::ASTSummarizer do
  it "summarizes classes, methods, requires, and full bodies for touched methods" do
    Dir.mktmpdir("ast-sum") do |root|
      File.write(File.join(root, "sample.rb"), <<~RUBY)
        require "json"
        class Foo
          def bar
            1
          end
          def baz
            2
          end
        end
      RUBY

      summarizer = described_class.new(workspace_root: root)
      out = summarizer.summarize(file_paths: ["sample.rb"], touched_methods: ["bar"])
      file = out[:files]["sample.rb"]

      expect(file[:requires]).to include("json")
      foo = file[:classes].find { |c| c[:name] == "Foo" }
      expect(foo[:methods]).to include("bar", "baz")
      expect(file[:touched_method_bodies]["bar"]).to include("1")
      expect(file[:touched_method_bodies]).not_to have_key("baz")
    end
  end

  it "records parse_error for invalid Ruby" do
    Dir.mktmpdir("ast-bad") do |root|
      File.write(File.join(root, "bad.rb"), "@@@")
      summarizer = described_class.new(workspace_root: root)
      out = summarizer.summarize(file_paths: ["bad.rb"], touched_methods: [])
      expect(out[:files]["bad.rb"]).to eq("parse_error")
    end
  end
end

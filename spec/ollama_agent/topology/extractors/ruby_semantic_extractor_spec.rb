# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Topology::Extractors::RubySemanticExtractor do
  let(:extractor) { described_class.new }

  it "extracts ClassNode and ModuleNode" do
    Dir.mktmpdir("topo-ir") do |root|
      path = File.join(root, "m.rb")
      File.write(path, <<~RUBY)
        module Outer
          class Inner < StandardError
            def hi; end
          end
        end
      RUBY
      nodes = extractor.extract(file_path: path)
      expect(nodes.map(&:class)).to contain_exactly(
        OllamaAgent::Topology::IR::ModuleNode,
        OllamaAgent::Topology::IR::ClassNode
      )
      inner = nodes.grep(OllamaAgent::Topology::IR::ClassNode).first
      expect(inner.fqcn).to eq("Outer::Inner")
      expect(inner.superclass_fqcn).to eq("StandardError")
    end
  end

  it "emits ConcernNode when ActiveSupport::Concern is extended" do
    Dir.mktmpdir("topo-concern") do |root|
      path = File.join(root, "c.rb")
      File.write(path, <<~RUBY)
        module MyConcern
          extend ActiveSupport::Concern
          def instance_level; end
          class_methods do
            def class_level; end
          end
        end
      RUBY
      nodes = extractor.extract(file_path: path)
      expect(nodes.size).to eq(1)
      expect(nodes.first).to be_a(OllamaAgent::Topology::IR::ConcernNode)
      expect(nodes.first.instance_methods).to include("instance_level")
      expect(nodes.first.class_methods).to include("class_level")
    end
  end

  it "reopening the same FQCN across files yields the same fqcn string" do
    Dir.mktmpdir("topo-reopen") do |root|
      a = File.join(root, "a.rb")
      b = File.join(root, "b.rb")
      File.write(a, "class Foo; def first; end; end")
      File.write(b, "class Foo; def second; end; end")
      fa = extractor.extract(file_path: a).grep(OllamaAgent::Topology::IR::ClassNode).first
      fb = extractor.extract(file_path: b).grep(OllamaAgent::Topology::IR::ClassNode).first
      expect(fa.fqcn).to eq("Foo")
      expect(fb.fqcn).to eq("Foo")
    end
  end

  it "returns an empty list and reports parse failures via on_parse_error" do
    errors = []
    extractor.on_parse_error = proc { |e| errors << e }
    Dir.mktmpdir("topo-bad") do |root|
      path = File.join(root, "bad.rb")
      File.write(path, "@@@")
      expect(extractor.extract(file_path: path)).to eq([])
      expect(errors.size).to eq(1)
      expect(errors.first).to be_a(described_class::ParseError)
    end
  end
end

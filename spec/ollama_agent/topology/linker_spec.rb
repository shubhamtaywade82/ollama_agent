# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Topology::Linker do
  def write_bar_fixtures(root)
    models = File.join(root, "app", "models")
    FileUtils.mkdir_p(models)
    write_foo_concern(models)
    bar_a = write_bar_one(models)
    bar_b = write_bar_two(models)
    bad = write_broken(models)
    { bar_a: bar_a, bar_b: bar_b, bad: bad }
  end

  def write_foo_concern(models)
    File.write(File.join(models, "foo_concern.rb"), <<~RUBY)
      module FooConcern
        extend ActiveSupport::Concern
        def from_concern_instance; end
        class_methods do
          def from_concern_class; end
        end
      end
    RUBY
  end

  def write_bar_one(models)
    path = File.join(models, "bar_one.rb")
    File.write(path, <<~RUBY)
      class Bar
        include FooConcern
        def from_first_file; end
      end
    RUBY
    path
  end

  def write_bar_two(models)
    path = File.join(models, "bar_two.rb")
    File.write(path, <<~RUBY)
      class Bar
        def from_second_file; end
      end
    RUBY
    path
  end

  def write_broken(models)
    path = File.join(models, "broken.rb")
    File.write(path, "@@@")
    path
  end

  def run_pipeline
    Dir.mktmpdir("linker-pipeline") do |root|
      paths = write_bar_fixtures(root)
      staged = OllamaAgent::Topology::StagedGraph.new
      linker = described_class.new(workspace_root: root, staged_graph: staged)
      result = linker.run(roots: ["app/models"])
      yield({ result: result, staged: staged, **paths })
    end
  end

  it "records parse errors and aggregates Bar across files with concern expansion" do
    run_pipeline do |ctx|
      expect(ctx[:result][:parse_errors].keys).to include(File.expand_path(ctx[:bad]))
      bar_meta = ctx[:result][:aggregated]["Bar"]
      names = bar_meta[:methods].map { |m| m[:name] || m["name"] }
      expect(names).to contain_exactly("from_first_file", "from_second_file")
      expect(bar_meta[:concern_instance_methods]).to include("from_concern_instance")
      expect(bar_meta[:concern_class_methods]).to include("from_concern_class")
      bar_files = committed_bar_files(ctx[:staged])
      expect(bar_files).to contain_exactly(File.expand_path(ctx[:bar_a]), File.expand_path(ctx[:bar_b]))
    end
  end

  it "rejects parse-failed files on promote without committing them" do
    run_pipeline do |ctx|
      expect(ctx[:staged].promote(file_path: ctx[:bad])).to eq(:rejected_parse_error)
    end
  end

  def committed_bar_files(staged)
    files = []
    staged.symbols.each do |sid|
      staged.committed_origins_for(symbol_id: sid).each do |o|
        node = o[:ir_node]
        next unless node.is_a?(OllamaAgent::Topology::IR::ClassNode)
        next unless node.fqcn == "Bar"

        files << o[:file_path]
      end
    end
    files
  end
end

# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe OllamaAgent::CLI::SkillCommand do
  describe "list" do
    it "prints registered skill names sorted alphabetically" do
      output = capture_stdout { described_class.new.list }

      lines = output.lines.map(&:strip)
      expect(lines).to include("architecture_refactor", "performance_optimizer", "debug_engineer", "feature_builder")
      expect(lines).to eq(lines.sort)
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end

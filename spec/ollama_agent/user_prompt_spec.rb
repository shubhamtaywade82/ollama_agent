# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::UserPrompt do
  it "reads yes from injected stdin for patch confirm" do
    stdin = StringIO.new("y\n")
    stdout = StringIO.new
    p = described_class.new(stdin: stdin, stdout: stdout)
    expect(p.confirm_patch("f.rb", "diff")).to be true
  end

  it "reads no from injected stdin" do
    stdin = StringIO.new("n\n")
    stdout = StringIO.new
    p = described_class.new(stdin: stdin, stdout: stdout)
    expect(p.confirm_write_file("f.rb", "body")).to be false
  end
end

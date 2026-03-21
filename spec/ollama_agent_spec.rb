# frozen_string_literal: true

RSpec.describe OllamaAgent do
  it "has a version number" do
    expect(OllamaAgent::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end
end

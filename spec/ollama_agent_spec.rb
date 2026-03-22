# frozen_string_literal: true

RSpec.describe OllamaAgent do
  it "has a version number" do
    expect(OllamaAgent::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  it "resolves gem_root to the lib/ parent directory" do
    expect(File.directory?(File.join(described_class.gem_root, "lib", "ollama_agent"))).to be(true)
  end
end

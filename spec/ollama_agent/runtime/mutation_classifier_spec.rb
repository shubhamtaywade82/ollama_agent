# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::MutationClassifier do
  it "classifies atomic_write as reversible" do
    expect(described_class.classify({ kind: "atomic_write" })).to eq(:reversible)
    expect(described_class.classify({ "kind" => "atomic_write" })).to eq(:reversible)
  end

  it "classifies http_post and shell_exec as irreversible" do
    expect(described_class.classify({ kind: "http_post" })).to eq(:irreversible)
    expect(described_class.classify({ kind: "shell_exec" })).to eq(:irreversible)
  end

  it "classifies unknown kinds as compensatable" do
    expect(described_class.classify({ kind: "other" })).to eq(:compensatable)
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::CriticalityPolicy do
  let(:node) do
    OllamaAgent::Security::OwnershipIndex.node(
      prefix: "app",
      owner: "application",
      mutable_in_modes: %w[normal replay],
      criticality: criticality,
      forbidden: forbidden
    )
  end

  let(:criticality) { "routine" }
  let(:forbidden) { false }

  around do |example|
    previous = described_class.audit_listener
    described_class.audit_listener = nil
    example.run
    described_class.audit_listener = previous
  end

  describe ".gate" do
    it "rejects forbidden nodes regardless of mode and criticality" do
      n = OllamaAgent::Security::OwnershipIndex.node(
        prefix: ".env",
        owner: "secrets",
        mutable_in_modes: OllamaAgent::Runtime::ExecutionMode::ALL,
        criticality: "routine",
        forbidden: true
      )

      expect(described_class.gate(n, mode: "normal")).to eq(:reject)
    end

    it "rejects when the execution mode is not listed on the node" do
      expect(described_class.gate(node, mode: "dry_run")).to eq(:reject)
    end

    it "allows routine criticality when mode matches" do
      expect(described_class.gate(node, mode: "normal")).to eq(:allow)
    end

    it "allows sensitive criticality and invokes the audit listener" do
      events = []
      described_class.audit_listener = proc do |node:, mode:|
        events << [node.prefix, mode]
      end
      sensitive = OllamaAgent::Security::OwnershipIndex.node(
        prefix: "config",
        owner: "platform",
        mutable_in_modes: %w[normal],
        criticality: "sensitive",
        forbidden: false
      )

      expect(described_class.gate(sensitive, mode: "normal")).to eq(:allow)
      expect(events).to eq([%w[config normal]])
    end

    it "requires a supervisor lease for critical criticality" do
      critical = OllamaAgent::Security::OwnershipIndex.node(
        prefix: "db/migrate",
        owner: "data",
        mutable_in_modes: %w[normal],
        criticality: "critical",
        forbidden: false
      )

      expect(described_class.gate(critical, mode: "normal")).to eq(:require_supervisor_lease)
    end

    it "rejects unknown criticality values" do
      odd = OllamaAgent::Security::OwnershipIndex.node(
        prefix: "x",
        owner: "y",
        mutable_in_modes: %w[normal],
        criticality: "weird",
        forbidden: false
      )

      expect(described_class.gate(odd, mode: "normal")).to eq(:reject)
    end

    it "rejects a nil node" do
      expect(described_class.gate(nil, mode: "normal")).to eq(:reject)
    end
  end
end

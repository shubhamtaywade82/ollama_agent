# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Security::OwnershipCompiler do
  let(:compiler) { described_class.new }

  def compile!(yaml)
    compiler.compile(yaml_string: yaml)
  end

  describe "#compile" do
    it "accepts a valid nested rules document" do
      yaml = <<~YAML
        rules:
          - prefix: app
            owner: application
            mutable_in_modes: [normal, replay]
            criticality: routine
            children:
              - prefix: app/models
                owner: domain
                mutable_in_modes: [normal]
                criticality: sensitive
      YAML

      index = compile!(yaml)

      expect(index).to be_a(OllamaAgent::Security::OwnershipIndex)
      expect(compiler.source_sha256).to eq(index.source_sha256)
    end

    it "rejects duplicate prefixes anywhere in the tree" do
      yaml = <<~YAML
        rules:
          - prefix: lib
            owner: a
            mutable_in_modes: [normal]
            criticality: routine
          - prefix: lib
            owner: b
            mutable_in_modes: [normal]
            criticality: routine
      YAML

      expect { compile!(yaml) }.to raise_error(
        OllamaAgent::Security::OwnershipCompileError,
        /duplicate prefix: lib/
      )
    end

    it "rejects ambiguous sibling prefixes (one is a strict prefix of another)" do
      yaml = <<~YAML
        rules:
          - prefix: app
            owner: a
            mutable_in_modes: [normal]
            criticality: routine
          - prefix: app/models
            owner: b
            mutable_in_modes: [normal]
            criticality: routine
      YAML

      expect { compile!(yaml) }.to raise_error(
        OllamaAgent::Security::OwnershipCompileError,
        /ambiguous sibling prefixes/
      )
    end

    it "rejects cycles in the children chain (repeated ancestor prefix)" do
      yaml = <<~YAML
        rules:
          - prefix: a
            owner: a1
            mutable_in_modes: [normal]
            criticality: routine
            children:
              - prefix: b
                owner: b1
                mutable_in_modes: [normal]
                criticality: routine
                children:
                  - prefix: a
                    owner: a2
                    mutable_in_modes: [normal]
                    criticality: routine
      YAML

      expect { compile!(yaml) }.to raise_error(
        OllamaAgent::Security::OwnershipCompileError,
        /cycle or duplicate prefix in ancestry/
      )
    end

    it "rejects privilege expansion (child mutable_in_modes not subset of parent)" do
      yaml = <<~YAML
        rules:
          - prefix: zone
            owner: z1
            mutable_in_modes: [normal, replay]
            criticality: routine
            children:
              - prefix: zone/inner
                owner: z2
                mutable_in_modes: [normal, replay, validation]
                criticality: routine
      YAML

      expect { compile!(yaml) }.to raise_error(
        OllamaAgent::Security::OwnershipCompileError,
        /privilege escalation/
      )
    end

    it "rejects invalid execution modes" do
      yaml = <<~YAML
        rules:
          - prefix: app
            owner: a
            mutable_in_modes: [normal, bogus]
            criticality: routine
      YAML

      expect { compile!(yaml) }.to raise_error(
        OllamaAgent::Security::OwnershipCompileError,
        /invalid mutable_in_modes/
      )
    end

    it "rejects invalid criticality labels" do
      yaml = <<~YAML
        rules:
          - prefix: app
            owner: a
            mutable_in_modes: [normal]
            criticality: ultra
      YAML

      expect { compile!(yaml) }.to raise_error(
        OllamaAgent::Security::OwnershipCompileError,
        /invalid criticality/
      )
    end
  end
end

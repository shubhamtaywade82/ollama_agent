# frozen_string_literal: true

# rubocop:disable Style/MultilineBlockChain -- RSpec raise_error matchers with attribute assertions
require "spec_helper"

RSpec.describe OllamaAgent::Runtime::PermissionBridge do
  def owners_routine
    <<~YAML
      rules:
        - prefix: lib
          owner: libraries
          mutable_in_modes: [normal, replay, validation, dry_run, shadow]
          criticality: routine
          children: []
    YAML
  end

  def owners_forbidden_lib
    <<~YAML
      rules:
        - prefix: lib
          owner: blocked
          mutable_in_modes: [normal, replay, validation, dry_run, shadow]
          criticality: routine
          forbidden: true
          children: []
    YAML
  end

  def build_index(yaml)
    OllamaAgent::Security::OwnershipCompiler.new.compile(yaml_string: yaml)
  end

  def with_bridge(yaml:, permissions:)
    Dir.mktmpdir("permission-bridge") do |root|
      bridge = described_class.new(
        permissions: permissions,
        policies: OllamaAgent::Runtime::Policies.new,
        ownership_index: build_index(yaml),
        workspace_root: root
      )
      yield bridge
    end
  end

  describe "#allow_mutation?" do
    it "returns true when legacy and kernel both allow the mutation" do
      with_bridge(yaml: owners_routine, permissions: OllamaAgent::Runtime::Permissions.new(profile: :full)) do |b|
        expect(b.allow_mutation?(tool_name: "write_file", path: "lib/a.rb", mode: "normal")).to be(true)
      end
    end

    it "returns false when both systems deny the mutation" do
      perms = OllamaAgent::Runtime::Permissions.new(profile: :read_only)
      with_bridge(yaml: owners_forbidden_lib, permissions: perms) do |b|
        expect(b.allow_mutation?(tool_name: "write_file", path: "lib/a.rb", mode: "normal")).to be(false)
      end
    end

    it "raises when legacy allows but kernel denies" do
      perms = OllamaAgent::Runtime::Permissions.new(profile: :full)
      with_bridge(yaml: owners_forbidden_lib, permissions: perms) do |b|
        expect do
          b.allow_mutation?(tool_name: "write_file", path: "lib/a.rb", mode: "normal")
        end.to raise_error(OllamaAgent::PermissionConflictError) do |err|
          expect(err.legacy_allowed).to be(true)
          expect(err.kernel_allowed).to be(false)
        end
      end
    end

    it "raises when legacy denies but kernel allows" do
      perms = OllamaAgent::Runtime::Permissions.new(profile: :read_only)
      with_bridge(yaml: owners_routine, permissions: perms) do |b|
        expect do
          b.allow_mutation?(tool_name: "write_file", path: "lib/a.rb", mode: "normal")
        end.to raise_error(OllamaAgent::PermissionConflictError) do |err|
          expect(err.legacy_allowed).to be(false)
          expect(err.kernel_allowed).to be(true)
        end
      end
    end
  end

  describe "#pipeline_allowed?" do
    let(:logger) { instance_double(Logger, warn: nil, error: nil) }

    it "returns true when legacy and kernel agree to allow" do
      perms = OllamaAgent::Runtime::Permissions.new(profile: :full)
      with_bridge(yaml: owners_routine, permissions: perms) do |b|
        expect(
          b.pipeline_allowed?(tool_name: "write_file", path: "lib/a.rb", mode: "normal", logger: logger)
        ).to be(true)
      end
    end

    it "returns false when both deny without logging divergence" do
      perms = OllamaAgent::Runtime::Permissions.new(profile: :read_only)
      with_bridge(yaml: owners_forbidden_lib, permissions: perms) do |b|
        expect(
          b.pipeline_allowed?(tool_name: "write_file", path: "lib/a.rb", mode: "normal", logger: logger)
        ).to be(false)
        expect(logger).not_to have_received(:warn)
        expect(logger).not_to have_received(:error)
      end
    end

    it "returns false and logs an error when legacy allows but kernel denies" do
      perms = OllamaAgent::Runtime::Permissions.new(profile: :full)
      with_bridge(yaml: owners_forbidden_lib, permissions: perms) do |b|
        expect(
          b.pipeline_allowed?(tool_name: "write_file", path: "lib/a.rb", mode: "normal", logger: logger)
        ).to be(false)
        expect(logger).to have_received(:error).with(/legacy allowed but kernel denied/)
      end
    end

    it "returns true and logs a warning when legacy denies but kernel allows" do
      perms = OllamaAgent::Runtime::Permissions.new(profile: :read_only)
      with_bridge(yaml: owners_routine, permissions: perms) do |b|
        expect(
          b.pipeline_allowed?(tool_name: "write_file", path: "lib/a.rb", mode: "normal", logger: logger)
        ).to be(true)
        expect(logger).to have_received(:warn).with(/legacy denied but kernel allowed/)
      end
    end
  end
end
# rubocop:enable Style/MultilineBlockChain

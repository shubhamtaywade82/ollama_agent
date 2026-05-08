# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Security::OwnershipIndex do
  let(:compiler) { OllamaAgent::Security::OwnershipCompiler.new }

  let(:index) do
    compiler.compile(yaml_string: <<~YAML)
      rules:
        - prefix: app
          owner: application
          mutable_in_modes: [normal]
          criticality: routine
          children:
            - prefix: app/models
              owner: domain
              mutable_in_modes: [normal]
              criticality: sensitive
        - prefix: lib
          owner: shared
          mutable_in_modes: [normal]
          criticality: routine
    YAML
  end

  describe "#lookup" do
    it "returns the longest matching prefix rule" do
      Dir.mktmpdir("ownership-index-lpm") do |workspace|
        target = File.join(workspace, "app", "models", "user.rb")
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, "# model")

        node = index.lookup(absolute_path: target, workspace_root: workspace)

        expect(node).not_to be_nil
        expect(node.prefix).to eq("app/models")
        expect(node.owner).to eq("domain")
        expect(node.criticality).to eq("sensitive")
      end
    end

    it "returns nil when the path is not under any configured prefix" do
      Dir.mktmpdir("ownership-index-unknown") do |workspace|
        target = File.join(workspace, "vendor", "bundle", "x.rb")
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, "x")

        expect(index.lookup(absolute_path: target, workspace_root: workspace)).to be_nil
      end
    end

    it "returns nil when the path contains path-traversal segments" do
      Dir.mktmpdir("ownership-index-dots") do |workspace|
        escaped = File.join(workspace, "lib", "..", "..", "etc", "passwd")

        expect(index.lookup(absolute_path: escaped, workspace_root: workspace)).to be_nil
      end
    end

    it "returns nil for symlinks that resolve outside the workspace" do
      skip "symlink not supported" unless File.respond_to?(:symlink)

      Dir.mktmpdir("ownership-index-outside") do |outside|
        Dir.mktmpdir("ownership-index-ws") do |workspace|
          File.write(File.join(outside, "secret.rb"), "nope")
          link = File.join(workspace, "escape")
          begin
            File.symlink(outside, link)
          rescue Errno::EPERM, NotImplementedError
            skip "symlink not permitted"
          end

          candidate = File.join(link, "secret.rb")

          expect(index.lookup(absolute_path: candidate, workspace_root: workspace)).to be_nil
        end
      end
    end
  end
end

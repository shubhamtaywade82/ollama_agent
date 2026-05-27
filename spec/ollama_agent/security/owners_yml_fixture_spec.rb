# frozen_string_literal: true

require "spec_helper"

RSpec.describe "config/ollama_agent/owners.yml" do
  it "loads, compiles, and resolves representative paths" do
    path = File.join(OllamaAgent.gem_root, "config", "ollama_agent", "owners.yml")
    expect(File.file?(path)).to be(true)

    compiler = OllamaAgent::Security::OwnershipCompiler.new
    index = compiler.compile(path: path)

    Dir.mktmpdir("owners-yml-fixture") do |workspace|
      models_file = File.join(workspace, "app", "models", "user.rb")
      FileUtils.mkdir_p(File.dirname(models_file))
      File.write(models_file, "class User; end")

      migrate_file = File.join(workspace, "db", "migrate", "20260101000000_create_users.rb")
      FileUtils.mkdir_p(File.dirname(migrate_file))
      File.write(migrate_file, "create_table :users")

      env_file = File.join(workspace, ".env")
      File.write(env_file, "SECRET=x")

      models_node = index.lookup(absolute_path: models_file, workspace_root: workspace)
      migrate_node = index.lookup(absolute_path: migrate_file, workspace_root: workspace)
      env_node = index.lookup(absolute_path: env_file, workspace_root: workspace)

      expect(models_node.owner).to eq("domain")
      expect(models_node.criticality).to eq("sensitive")

      expect(migrate_node.owner).to eq("data")
      expect(migrate_node.criticality).to eq("critical")

      expect(env_node.owner).to eq("secrets")
      expect(env_node.criticality).to eq("critical")
      expect(env_node.forbidden).to be(true)
    end
  end
end

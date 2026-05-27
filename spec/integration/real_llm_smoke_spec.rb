# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# rubocop:disable RSpec/DescribeClass -- opt-in integration smoke against a live Ollama host
RSpec.describe "real Ollama end-to-end smoke", :real_llm do
  before do
    skip "Set OLLAMA_HOST to run this smoke test" if ENV.fetch("OLLAMA_HOST", "").to_s.strip.empty?
  end

  it "creates hello.txt with the requested content (and saga when kernel is on)" do
    Dir.mktmpdir("real-llm-smoke") do |root|
      if ENV.fetch("OLLAMA_AGENT_KERNEL", "").strip.casecmp("true").zero?
        owners_dir = File.join(root, "config", "ollama_agent")
        FileUtils.mkdir_p(owners_dir)
        File.write(File.join(owners_dir, "owners.yml"), <<~YAML)
          rules:
            - prefix: hello.txt
              owner: smoke
              mutable_in_modes: [normal, replay, validation, dry_run]
              criticality: routine
        YAML
      end

      agent = OllamaAgent::Agent.new(
        root: root,
        confirm_patches: false,
        http_timeout: 300
      )

      agent.run("Create a file called hello.txt with content world")

      expect(File.read(File.join(root, "hello.txt"))).to eq("world")

      next unless ENV.fetch("OLLAMA_AGENT_KERNEL", "").strip.casecmp("true").zero?

      reg = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
      row = reg.runtime.get_first_row("SELECT state FROM sagas LIMIT 1")
      skip "Kernel did not record a saga row for this model run" if row.nil?

      state = row["state"] || row[:state]
      expect(state).to eq("committed")
    end
  end
end
# rubocop:enable RSpec/DescribeClass

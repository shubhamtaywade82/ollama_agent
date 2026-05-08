# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::Runtime::DatabaseRegistry do
  describe "#event_store and #runtime" do
    it "creates idempotent schema for both databases under .ollama_agent/kernel" do
      Dir.mktmpdir("db-registry") do |root|
        registry = described_class.new(root_dir: root)
        event_db = registry.event_store
        runtime_db = registry.runtime

        expect(event_db.table_info("events")).not_to be_empty

        %w[workspace_fingerprints fencing_tokens integration_queue].each do |table|
          expect(runtime_db.table_info(table)).not_to be_empty
        end

        # Second open reuses schema without error
        described_class.new(root_dir: root).event_store
        described_class.new(root_dir: root).runtime
      end
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "sqlite3"

RSpec.describe OllamaAgent::Runtime::SchemaMigrator do
  def registry_for(tmp)
    OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: tmp)
  end

  it "applies all migrations on a fresh kernel directory" do
    Dir.mktmpdir("schema-migrator") do |tmp|
      reg = registry_for(tmp)
      migrator = described_class.new(db_registry: reg)
      applied = migrator.migrate!
      expect(applied).to eq([1, 2])

      rt = reg.runtime
      expect(rt.table_info("cost_ledger")).not_to be_empty
      es = reg.event_store
      expect(es.table_info("events")).not_to be_empty
    end
  end

  it "applies only pending migrations after a partial schema_migrations state" do
    Dir.mktmpdir("schema-migrator-partial") do |tmp|
      reg = registry_for(tmp)
      described_class.new(db_registry: reg).migrate!

      runtime_path = File.join(reg.kernel_dir, "runtime.db")
      db = SQLite3::Database.new(runtime_path)
      db.execute("DELETE FROM schema_migrations WHERE version = ?", 2)
      db.close

      applied = described_class.new(db_registry: reg).migrate!
      expect(applied).to eq([2])

      db = SQLite3::Database.new(runtime_path)
      db.results_as_hash = true
      row = db.get_first_row("SELECT COUNT(*) AS c FROM schema_migrations WHERE version = ?", 2)
      expect(row["c"].to_i).to eq(1)
      db.close
    end
  end

  it "is a no-op when rerun after everything is applied" do
    Dir.mktmpdir("schema-migrator-idem") do |tmp|
      reg = registry_for(tmp)
      m = described_class.new(db_registry: reg)
      expect(m.migrate!).to eq([1, 2])
      expect(m.migrate!).to eq([])
    end
  end
end
